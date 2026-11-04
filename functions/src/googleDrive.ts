import { createCipheriv, createDecipheriv, randomBytes, createHash } from "node:crypto";
import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onRequest } from "firebase-functions/v2/https";
import { getAuth } from "firebase-admin/auth";

if (!getApps().length) initializeApp();
const db = getFirestore();
const clientId = defineSecret("GOOGLE_CLIENT_ID");
const clientSecret = defineSecret("GOOGLE_CLIENT_SECRET");
const redirectUri = defineSecret("GOOGLE_REDIRECT_URI");
const encryptionKey = defineSecret("GOOGLE_TOKEN_ENCRYPTION_KEY");

function keyBytes(): Buffer {
  const key = Buffer.from(encryptionKey.value(), "base64");
  if (key.length !== 32) throw new Error("GOOGLE_TOKEN_ENCRYPTION_KEY must be 32-byte base64.");
  return key;
}
function encrypt(value: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", keyBytes(), iv);
  const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), encrypted]).toString("base64");
}
function decrypt(value: string): string {
  const raw = Buffer.from(value, "base64");
  if (raw.length < 29) throw new Error("Stored Drive token is invalid.");
  const decipher = createDecipheriv("aes-256-gcm", keyBytes(), raw.subarray(0, 12));
  decipher.setAuthTag(raw.subarray(12, 28));
  return Buffer.concat([decipher.update(raw.subarray(28)), decipher.final()]).toString("utf8");
}
function sha(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
async function bearerUid(req: import("express").Request): Promise<string> {
  const header = String(req.headers.authorization ?? "");
  if (!header.startsWith("Bearer ")) throw new HttpsError("unauthenticated", "Firebase sign-in required.");
  return (await getAuth().verifyIdToken(header.slice(7))).uid;
}

export const startGoogleDriveOAuth = onRequest(
  { region: "asia-south1", secrets: [clientId, clientSecret, redirectUri, encryptionKey] },
  async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({ error: "POST_REQUIRED" }); return; }
      const uid = await bearerUid(req);
      const state = randomBytes(32).toString("hex");
      await db.collection("googleDriveOAuthStates").doc(sha(state)).create({
        customerUid: uid,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      });
      const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
      url.search = new URLSearchParams({
        client_id: clientId.value(),
        redirect_uri: redirectUri.value(),
        response_type: "code",
        scope: "openid email https://www.googleapis.com/auth/drive.file",
        access_type: "offline",
        prompt: "consent",
        state,
      }).toString();
      res.set("Cache-Control", "no-store").json({ ok: true, authorizationUrl: url.toString() });
    } catch (error) {
      const status = error instanceof HttpsError ? (error.code === "unauthenticated" ? 401 : 400) : 500;
      res.status(status).json({ error: error instanceof Error ? error.message : "OAUTH_START_FAILED" });
    }
  },
);

export const googleDriveOAuthCallback = onRequest(
  { region: "asia-south1", secrets: [clientId, clientSecret, redirectUri, encryptionKey] },
  async (req, res) => {
    try {
      const code = String(req.query.code ?? "");
      const state = String(req.query.state ?? "");
      if (!code || !/^[a-f0-9]{64}$/.test(state)) { res.status(400).send("Invalid Google authorization response."); return; }
      const stateRef = db.collection("googleDriveOAuthStates").doc(sha(state));
      const stateSnap = await stateRef.get();
      if (!stateSnap.exists || stateSnap.get("expiresAt").toDate().getTime() < Date.now()) {
        res.status(400).send("This Google Drive connection request expired. Return to the app and try again."); return;
      }
      const uid = String(stateSnap.get("customerUid"));
      const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          code, client_id: clientId.value(), client_secret: clientSecret.value(),
          redirect_uri: redirectUri.value(), grant_type: "authorization_code",
        }),
      });
      const tokens = await tokenResponse.json() as Record<string, any>;
      if (!tokenResponse.ok || typeof tokens.refresh_token !== "string") {
        res.status(400).send("Google did not return offline Drive access. Reconnect and approve access."); return;
      }
      const profileResponse = await fetch("https://www.googleapis.com/oauth2/v2/userinfo", {
        headers: { Authorization: "Bearer " + String(tokens.access_token) },
      });
      const profile = await profileResponse.json() as Record<string, any>;
      if (!profileResponse.ok || typeof profile.email !== "string") {
        res.status(502).send("Google account details could not be verified."); return;
      }
      await db.runTransaction(async tx => {
        const fresh = await tx.get(stateRef);
        if (!fresh.exists || fresh.get("customerUid") !== uid) throw new Error("OAUTH_STATE_ALREADY_USED");
        tx.delete(stateRef);
        tx.set(db.collection("googleDriveConnections").doc(uid), {
          customerUid: uid,
          encryptedRefreshToken: encrypt(tokens.refresh_token),
          googleEmail: profile.email,
          driveFolderId: null,
          connectedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        tx.create(db.collection("auditEvents").doc(), {
          actorUid: uid, orderId: uid, eventType: "google_drive_connected",
          eventData: { googleEmail: profile.email }, createdAt: FieldValue.serverTimestamp(),
        });
      });
      res.redirect(302, "weddingvideoshare://drive-connected?status=success");
    } catch (error) {
      res.status(400).send(error instanceof Error ? error.message : "Google Drive connection failed.");
    }
  },
);

export async function getGoogleDriveAccessToken(uid: string): Promise<{ accessToken: string; email: string }> {
  const snap = await db.collection("googleDriveConnections").doc(uid).get();
  if (!snap.exists) throw new HttpsError("failed-precondition", "Connect Google Drive first.");
  const refreshToken = decrypt(String(snap.get("encryptedRefreshToken")));
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId.value(), client_secret: clientSecret.value(),
      refresh_token: refreshToken, grant_type: "refresh_token",
    }),
  });
  const tokens = await response.json() as Record<string, any>;
  if (!response.ok || typeof tokens.access_token !== "string") {
    throw new HttpsError("unauthenticated", "Google Drive authorization expired. Reconnect Drive.");
  }
  return { accessToken: tokens.access_token, email: String(snap.get("googleEmail")) };
}
