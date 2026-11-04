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

const MAX_VIDEO_BYTES = 40_000_000_000;
function safeFilename(value: unknown): string {
  const name = String(value ?? "").trim();
  if (!name || name.length > 240 || name.includes("/") || name.includes("\\") || /[\x00-\x1f]/.test(name)) {
    throw new HttpsError("invalid-argument", "A valid video filename is required.");
  }
  return name;
}
function safeMime(value: unknown): string {
  const mime = String(value ?? "application/octet-stream");
  const slash = mime.indexOf("/");
  if (slash <= 0 || slash !== mime.lastIndexOf("/") ||
      !/^[a-z0-9.+-]+$/i.test(mime.slice(0, slash)) ||
      !/^[a-z0-9.+-]+$/i.test(mime.slice(slash + 1))) {
    throw new HttpsError("invalid-argument", "Invalid video MIME type.");
  }
  return mime;
}
async function driveRequest(accessToken: string, url: string, init: RequestInit = {}): Promise<Response> {
  return fetch(url, { ...init, headers: { Authorization: "Bearer " + accessToken, ...(init.headers ?? {}) } });
}

export const startGoogleDriveUpload = onRequest(
  { region: "asia-south1", secrets: [clientId, clientSecret, redirectUri, encryptionKey] },
  async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({ error: "POST_REQUIRED" }); return; }
      const uid = await bearerUid(req);
      const filename = safeFilename(req.body?.filename);
      const mimeType = safeMime(req.body?.mimeType);
      const sizeBytes = Number(req.body?.sizeBytes);
      const orderId = String(req.body?.orderId ?? "");
      if (!Number.isSafeInteger(sizeBytes) || sizeBytes <= 0 || sizeBytes > MAX_VIDEO_BYTES) {
        throw new HttpsError("invalid-argument", "Video must be between 1 byte and 40 GB.");
      }
      if (orderId !== uid) throw new HttpsError("permission-denied", "Order does not belong to this customer.");
      const order = await db.collection("weddingOrders").doc(uid).get();
      if (!order.exists || order.get("customerUid") !== uid || order.get("uploadLocked") === true) {
        throw new HttpsError("failed-precondition", "A new wedding upload is not available for this account.");
      }
      const existing = await db.collection("weddingVideos").where("customerUid", "==", uid).limit(1).get();
      if (!existing.empty) {
        throw new HttpsError("already-exists", "An upload already exists for this account. Resume that upload instead of starting another.");
      }
      const { accessToken, email } = await getGoogleDriveAccessToken(uid);
      const metadata = { name: filename, mimeType, description: "Wedding Video Share upload for customer " + uid };
      const response = await driveRequest(accessToken,
        "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,name,mimeType",
        { method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8", "X-Upload-Content-Type": mimeType, "X-Upload-Content-Length": String(sizeBytes) }, body: JSON.stringify(metadata) });
      const uploadUrl = response.headers.get("location");
      if (!response.ok || !uploadUrl || !uploadUrl.startsWith("https://www.googleapis.com/upload/drive/")) {
        throw new HttpsError("unavailable", "Google Drive could not start a resumable upload session.");
      }
      const videoRef = db.collection("weddingVideos").doc(uid);
      await db.runTransaction(async tx => {
        const freshOrder = await tx.get(db.collection("weddingOrders").doc(uid));
        const freshVideo = await tx.get(videoRef);
        if (!freshOrder.exists || freshOrder.get("customerUid") !== uid ||
            freshOrder.get("uploadLocked") === true || freshVideo.exists) {
          throw new HttpsError("failed-precondition", "This account is not eligible for another upload.");
        }
        tx.set(videoRef, {
          customerUid: uid, orderId: uid, originalFilename: filename,
          mimeType, fileSizeBytes: sizeBytes, uploadStatus: "uploading",
          googleDriveAccountEmail: email, autoDeleteConsentAt: null,
          deletedAt: null, createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        tx.set(db.collection("googleDriveUploadSessions").doc(uid), {
          customerUid: uid, orderId: uid, filename, mimeType, sizeBytes,
          uploadUrl, createdAt: FieldValue.serverTimestamp(),
        });
      });
      res.set("Cache-Control", "no-store").json({ ok: true, uploadUrl, resumeOffset: 0 });
    } catch (error) {
      const status = error instanceof HttpsError ? (error.code === "unauthenticated" ? 401 : 400) : 500;
      res.status(status).json({ error: error instanceof Error ? error.message : "UPLOAD_START_FAILED" });
    }
  },
);


export const resumeGoogleDriveUpload = onRequest(
  { region: "asia-south1", secrets: [clientId, clientSecret, redirectUri, encryptionKey] },
  async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({ error: "POST_REQUIRED" }); return; }
      const uid = await bearerUid(req);
      const sessionRef = db.collection("googleDriveUploadSessions").doc(uid);
      const snap = await sessionRef.get();
      if (!snap.exists || snap.get("customerUid") !== uid || snap.get("orderId") !== uid) {
        throw new HttpsError("not-found", "No resumable upload session was found.");
      }
      const uploadUrl = String(snap.get("uploadUrl") ?? "");
      if (!uploadUrl.startsWith("https://www.googleapis.com/upload/drive/")) {
        throw new HttpsError("failed-precondition", "The saved upload session is invalid.");
      }
      const expectedSizeBytes = Number(snap.get("sizeBytes"));
      if (!Number.isSafeInteger(expectedSizeBytes) || expectedSizeBytes <= 0 || expectedSizeBytes > MAX_VIDEO_BYTES) {
        throw new HttpsError("failed-precondition", "Saved upload size is invalid.");
      }
      const { accessToken } = await getGoogleDriveAccessToken(uid);
      // Google Drive's resumable protocol reports the server-accepted byte
      // offset via a zero-byte PUT status probe. Never trust a client offset.
      const probe = await driveRequest(accessToken, uploadUrl, {
        method: "PUT",
        headers: { "Content-Length": "0", "Content-Range": "bytes */" + expectedSizeBytes },
      });
      if (probe.status === 308) {
        const range = probe.headers.get("range") ?? "";
        const match = /^bytes=0-(\\d+)$/.exec(range);
        const resumeOffset = match ? Number(match[1]) + 1 : 0;
        if (!Number.isSafeInteger(resumeOffset) || resumeOffset > expectedSizeBytes) {
          throw new HttpsError("data-loss", "Google Drive returned an invalid upload offset.");
        }
        res.set("Cache-Control", "no-store").json({
          ok: true, uploadUrl, filename: snap.get("filename"),
          mimeType: snap.get("mimeType"), expectedSizeBytes, resumeOffset,
          uploadComplete: false,
        });
        return;
      }
      if (probe.status === 200 || probe.status === 201) {
        const completed = await probe.json() as Record<string, any>;
        res.set("Cache-Control", "no-store").json({
          ok: true, filename: snap.get("filename"), mimeType: snap.get("mimeType"),
          expectedSizeBytes, resumeOffset: expectedSizeBytes, uploadComplete: true,
          fileId: String(completed.id ?? ""),
        });
        return;
      }
      if (probe.status === 404 || probe.status === 410) {
        throw new HttpsError("failed-precondition", "Google Drive upload session expired. Start a new upload.");
      }
      throw new HttpsError("unavailable", "Google Drive could not confirm the resumable upload position.");
    } catch (error) {
      const status = error instanceof HttpsError
        ? (error.code === "unauthenticated" ? 401 : error.code === "not-found" ? 404 : 400)
        : 500;
      res.status(status).json({ error: error instanceof Error ? error.message : "UPLOAD_RESUME_FAILED" });
    }
  },
);

export const finalizeGoogleDriveUpload = onRequest(
  { region: "asia-south1", secrets: [clientId, clientSecret, redirectUri, encryptionKey] },
  async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({ error: "POST_REQUIRED" }); return; }
      const uid = await bearerUid(req);
      const fileId = String(req.body?.fileId ?? "");
      if (!/^[a-zA-Z0-9_-]{10,200}$/.test(fileId)) throw new HttpsError("invalid-argument", "Invalid Google Drive file ID.");
      const sessionRef = db.collection("googleDriveUploadSessions").doc(uid);
      const [session, video] = await Promise.all([
        sessionRef.get(), db.collection("weddingVideos").doc(uid).get(),
      ]);
      if (!session.exists || !video.exists || session.get("customerUid") !== uid ||
          video.get("customerUid") !== uid || video.get("uploadStatus") !== "uploading") {
        throw new HttpsError("failed-precondition", "No matching upload is awaiting verification.");
      }
      const { accessToken, email } = await getGoogleDriveAccessToken(uid);
      const response = await driveRequest(accessToken,
        "https://www.googleapis.com/drive/v3/files/" + encodeURIComponent(fileId) + "?fields=id,name,mimeType,size,trashed,owners(emailAddress)");
      const meta = await response.json() as Record<string, any>;
      const size = Number(meta.size);
      if (!response.ok || meta.id !== fileId || meta.trashed === true ||
          meta.name !== session.get("filename") || meta.mimeType !== session.get("mimeType") ||
          size !== session.get("sizeBytes") || size <= 0 || size > MAX_VIDEO_BYTES) {
        throw new HttpsError("failed-precondition", "Google Drive file metadata does not match the expected complete upload.");
      }
      await db.runTransaction(async tx => {
        const freshSession = await tx.get(sessionRef);
        const videoRef = db.collection("weddingVideos").doc(uid);
        const orderRef = db.collection("weddingOrders").doc(uid);
        const [freshVideo, freshOrder] = await Promise.all([tx.get(videoRef), tx.get(orderRef)]);
        if (!freshSession.exists || !freshVideo.exists || !freshOrder.exists ||
            freshOrder.get("customerUid") !== uid || freshOrder.get("uploadLocked") === true ||
            freshSession.get("customerUid") !== uid ||
            freshSession.get("filename") !== meta.name ||
            freshSession.get("sizeBytes") !== size ||
            freshVideo.get("uploadStatus") !== "uploading") {
          throw new HttpsError("aborted", "Upload verification state changed. Please retry.");
        }
        tx.update(videoRef, {
          googleDriveFileId: fileId, originalFilename: meta.name,
          fileSizeBytes: size, mimeType: meta.mimeType,
          googleDriveAccountEmail: email, uploadStatus: "uploaded",
          uploadedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
        });
        // Lock this account's single video slot as soon as the full upload is
        // verified. Payment/share can happen afterwards, but a second upload
        // must never replace this verified video.
        tx.update(orderRef, {
          uploadLocked: true,
          workflowStatus: "video_uploaded_pending_payment",
          updatedAt: FieldValue.serverTimestamp(),
        });
        tx.delete(sessionRef);
        tx.create(db.collection("auditEvents").doc(), {
          actorUid: uid, orderId: uid, eventType: "google_drive_upload_verified",
          eventData: { fileId, sizeBytes: size }, createdAt: FieldValue.serverTimestamp(),
        });
      });
      res.json({ ok: true, fileId, sizeBytes: size, uploadStatus: "uploaded" });
    } catch (error) {
      const status = error instanceof HttpsError ? (error.code === "unauthenticated" ? 401 : 400) : 500;
      res.status(status).json({ error: error instanceof Error ? error.message : "UPLOAD_VERIFY_FAILED" });
    }
  },
);
