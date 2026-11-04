import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { getGoogleDriveAccessToken } from "./googleDrive";

if (!getApps().length) initializeApp();
const db = getFirestore();
const clientId = defineSecret("GOOGLE_CLIENT_ID");
const clientSecret = defineSecret("GOOGLE_CLIENT_SECRET");
const encryptionKey = defineSecret("GOOGLE_TOKEN_ENCRYPTION_KEY");
const workerSecret = defineSecret("DOWNLOAD_WORKER_SECRET");
const MAX_VIDEO_BYTES = 40_000_000_000;
const hash = (value: string) => createHash("sha256").update(value).digest("hex");
function safeHexEqual(a: string, b: string): boolean {
  if (!/^[a-f0-9]{64}$/.test(a) || !/^[a-f0-9]{64}$/.test(b)) return false;
  return timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
}

function requireUid(request: { auth?: { uid: string } | null }): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please sign in to continue.");
  return uid;
}

export const createWeddingShare = onCall(async (request) => {
  const uid = requireUid(request);
  const [order, video] = await Promise.all([
    db.collection("weddingOrders").doc(uid).get(),
    db.collection("weddingVideos").doc(uid).get(),
  ]);
  if (!order.exists || order.get("customerUid") !== uid ||
      order.get("paymentStatus") !== "paid") {
    throw new HttpsError("failed-precondition", "Verify the ₹290 payment before creating a share link.");
  }
  if (!video.exists || video.get("customerUid") !== uid ||
      video.get("uploadStatus") !== "uploaded" || !video.get("googleDriveFileId") ||
      !video.get("autoDeleteConsentAt")) {
    throw new HttpsError("failed-precondition", "A verified video and active Drive deletion consent are required.");
  }
  const size = Number(video.get("fileSizeBytes"));
  if (!Number.isSafeInteger(size) || size <= 0 || size > MAX_VIDEO_BYTES) {
    throw new HttpsError("failed-precondition", "The saved video size is invalid.");
  }
  const token = randomBytes(32).toString("hex");
  const pin = String(randomBytes(4).readUInt32BE(0) % 1_000_000).padStart(6, "0");
  const shareRef = db.collection("shareLinks").doc(uid);
  await db.runTransaction(async (tx) => {
    const [freshOrder, freshVideo] = await Promise.all([
      tx.get(db.collection("weddingOrders").doc(uid)),
      tx.get(db.collection("weddingVideos").doc(uid)),
    ]);
    if (!freshOrder.exists || freshOrder.get("paymentStatus") !== "paid" ||
        !freshVideo.exists || freshVideo.get("uploadStatus") !== "uploaded" ||
        !freshVideo.get("autoDeleteConsentAt") || freshVideo.get("deletedAt")) {
      throw new HttpsError("failed-precondition", "The wedding video is no longer eligible for sharing.");
    }
    tx.set(shareRef, {
      customerUid: uid, orderId: uid, videoId: uid,
      tokenHash: hash(token), pinHash: hash(token + ":" + pin),
      pinAttempts: 0, pinLockedUntil: null, isActive: true,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("auditEvents").doc(), {
      actorUid: uid, orderId: uid, eventType: "wedding_share_created",
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {
    ok: true,
    shareUrl: "https://asia-south1-wedding-video-share.cloudfunctions.net/weddingShareRedirect?token=" + token,
    downloadPin: pin,
    note: "Send the private link and six-digit PIN separately. Five wrong attempts lock the PIN for 15 minutes.",
  };
});

export const weddingShareWorkerControl = onRequest(
  { region: "asia-south1", secrets: [clientId, clientSecret, encryptionKey, workerSecret] },
  async (req, res) => {
    res.set("Cache-Control", "no-store");
    if (req.method !== "POST") { res.status(405).json({ error: "POST_REQUIRED" }); return; }
    const supplied = String(req.headers["x-download-worker-secret"] ?? "");
    if (!supplied || !safeHexEqual(hash(supplied), hash(workerSecret.value()))) {
      res.status(401).json({ error: "WORKER_AUTH_FAILED" }); return;
    }
    try {
      const body = req.body ?? {};
      if (body.action === "worker_prepare") {
        const token = String(body.token ?? "");
        const pin = String(body.pin ?? "");
        if (!/^[a-f0-9]{64}$/.test(token) || !/^\d{6}$/.test(pin)) {
          res.status(400).json({ error: "SHARE_OR_PIN_INVALID" }); return;
        }
        const shareQuery = await db.collection("shareLinks").where("tokenHash", "==", hash(token)).limit(1).get();
        if (shareQuery.empty) { res.status(404).json({ error: "SHARE_INVALID" }); return; }
        const shareDoc = shareQuery.docs[0];
        const share = shareDoc.data();
        const now = Date.now();
        const lockedUntil = share.pinLockedUntil?.toDate?.()?.getTime?.() ?? 0;
        if (share.isActive !== true || lockedUntil > now) {
          res.status(403).json({ error: "PIN_INVALID_OR_LOCKED" }); return;
        }
        const candidate = hash(token + ":" + pin);
        if (!safeHexEqual(candidate, String(share.pinHash ?? ""))) {
          await db.runTransaction(async tx => {
            const fresh = await tx.get(shareDoc.ref);
            if (!fresh.exists || fresh.get("tokenHash") !== hash(token)) return;
            const attempts = Number(fresh.get("pinAttempts") ?? 0) + 1;
            tx.update(shareDoc.ref, {
              pinAttempts: attempts >= 5 ? 0 : attempts,
              pinLockedUntil: attempts >= 5 ? new Date(now + 15 * 60 * 1000) : null,
              updatedAt: FieldValue.serverTimestamp(),
            });
          });
          res.status(403).json({ error: "PIN_INVALID_OR_LOCKED" }); return;
        }
        const [order, video] = await Promise.all([
          db.collection("weddingOrders").doc(String(share.customerUid)).get(),
          db.collection("weddingVideos").doc(String(share.videoId)).get(),
        ]);
        if (!order.exists || order.get("paymentStatus") !== "paid" ||
            !video.exists || video.get("uploadStatus") !== "uploaded" ||
            !video.get("autoDeleteConsentAt") || video.get("deletedAt")) {
          res.status(404).json({ error: "VIDEO_UNAVAILABLE" }); return;
        }
        const expectedBytes = Number(video.get("fileSizeBytes"));
        if (!Number.isSafeInteger(expectedBytes) || expectedBytes <= 0 || expectedBytes > MAX_VIDEO_BYTES) {
          res.status(503).json({ error: "VIDEO_SIZE_INVALID" }); return;
        }
        const { accessToken } = await getGoogleDriveAccessToken(String(share.customerUid));
        const metadataResponse = await fetch(
          "https://www.googleapis.com/drive/v3/files/" + encodeURIComponent(String(video.get("googleDriveFileId"))) + "?fields=id,size,trashed",
          { headers: { Authorization: "Bearer " + accessToken } },
        );
        const metadata = await metadataResponse.json() as Record<string, any>;
        if (!metadataResponse.ok || metadata.trashed === true || Number(metadata.size) !== expectedBytes) {
          res.status(503).json({ error: "DRIVE_FILE_NOT_VERIFIED" }); return;
        }
        const downloadRef = db.collection("receiverDownloads").doc();
        await db.runTransaction(async tx => {
          const freshShare = await tx.get(shareDoc.ref);
          if (!freshShare.exists || freshShare.get("isActive") !== true ||
              freshShare.get("tokenHash") !== hash(token) ||
              freshShare.get("pinHash") !== candidate) {
            throw new Error("SHARE_CHANGED");
          }
          tx.update(shareDoc.ref, { pinAttempts: 0, pinLockedUntil: null, updatedAt: FieldValue.serverTimestamp() });
          tx.create(downloadRef, {
            customerUid: share.customerUid, orderId: share.orderId,
            videoId: share.videoId, shareId: shareDoc.id, status: "downloading",
            bytesExpected: expectedBytes, bytesTransferred: 0,
            transferVerified: false, checksumVerified: false,
            createdAt: FieldValue.serverTimestamp(),
          });
          tx.create(db.collection("auditEvents").doc(), {
            actorUid: share.customerUid, orderId: share.orderId,
            eventType: "receiver_download_started",
            eventData: { downloadId: downloadRef.id }, createdAt: FieldValue.serverTimestamp(),
          });
        });
        res.json({
          ok: true, downloadId: downloadRef.id, shareLinkId: shareDoc.id,
          googleAccessToken: accessToken, fileId: String(video.get("googleDriveFileId")),
          filename: String(video.get("originalFilename") ?? "wedding-video"),
          mimeType: String(video.get("mimeType") ?? "application/octet-stream"),
          expectedBytes,
        });
        return;
      }
      if (body.action === "worker_complete") {
        const downloadId = String(body.downloadId ?? "");
        const shareId = String(body.shareLinkId ?? "");
        const bytes = Number(body.bytesTransferred ?? -1);
        const completed = body.completed === true;
        const downloadRef = db.collection("receiverDownloads").doc(downloadId);
        const snap = await downloadRef.get();
        if (!snap.exists || snap.get("shareId") !== shareId) {
          res.status(404).json({ error: "DOWNLOAD_SESSION_NOT_FOUND" }); return;
        }
        const expected = Number(snap.get("bytesExpected"));
        const valid = completed && Number.isSafeInteger(bytes) && bytes === expected;
        if (snap.get("status") !== "completed") {
          await db.runTransaction(async tx => {
            const fresh = await tx.get(downloadRef);
            if (!fresh.exists || fresh.get("shareId") !== shareId) throw new Error("DOWNLOAD_SESSION_NOT_FOUND");
            if (fresh.get("status") === "completed") return;
            tx.update(downloadRef, {
              status: valid ? "completed" : "interrupted",
              bytesTransferred: Math.max(0, Math.min(expected, Number.isFinite(bytes) ? bytes : 0)),
              transferVerified: valid, checksumVerified: false,
              completedAt: valid ? FieldValue.serverTimestamp() : null,
              verifiedAt: valid ? FieldValue.serverTimestamp() : null,
            });
            if (valid) {
              tx.create(db.collection("customerNotifications").doc(downloadId), {
                customerUid: fresh.get("customerUid"),
                orderId: fresh.get("orderId"),
                sourceDownloadId: downloadId,
                notificationType: "receiver_download_completed",
                title: "Wedding video download completed",
                message: "The server verified that the full video was streamed. Your Google Drive copy is deleted only if you gave consent; otherwise it remains saved.",
                createdAt: FieldValue.serverTimestamp(),
              });
            }
          });
        }
        if (!valid && snap.get("status") !== "completed") {
          res.json({ ok: true, completed: false, deleted: false }); return;
        }
        const videoRef = db.collection("weddingVideos").doc(String(snap.get("videoId")));
        const video = await videoRef.get();
        if (!video.exists || !video.get("autoDeleteConsentAt")) {
          res.json({ ok: true, completed: true, deleted: false, deleteReason: "CONSENT_NOT_FOUND" }); return;
        }
        if (video.get("uploadStatus") === "deleted" || !video.get("googleDriveFileId")) {
          res.json({ ok: true, completed: true, deleted: true }); return;
        }
        try {
          // Reserve the consented deletion atomically before calling Google.
          // Consent withdrawal rejects deletion_pending, closing the race where
          // a customer could revoke consent while the Drive DELETE was in flight.
          const deletionAllowed = await db.runTransaction(async tx => {
            const [freshVideo, freshDownload] = await Promise.all([tx.get(videoRef), tx.get(downloadRef)]);
            if (!freshVideo.exists || !freshDownload.exists ||
                freshDownload.get("status") !== "completed" ||
                freshDownload.get("transferVerified") !== true ||
                freshDownload.get("bytesTransferred") !== freshDownload.get("bytesExpected") ||
                !freshVideo.get("autoDeleteConsentAt")) return false;
            if (freshVideo.get("uploadStatus") === "deleted" ||
                freshVideo.get("uploadStatus") === "deletion_pending") return true;
            if (freshVideo.get("uploadStatus") !== "uploaded") return false;
            tx.update(videoRef, { uploadStatus: "deletion_pending", updatedAt: FieldValue.serverTimestamp() });
            return true;
          });
          if (!deletionAllowed) {
            res.json({ ok: true, completed: true, deleted: false, deleteReason: "CONSENT_OR_STATE_CHANGED" }); return;
          }
          const { accessToken } = await getGoogleDriveAccessToken(String(snap.get("customerUid")));
          const deletion = await fetch(
            "https://www.googleapis.com/drive/v3/files/" + encodeURIComponent(String(video.get("googleDriveFileId"))),
            { method: "DELETE", headers: { Authorization: "Bearer " + accessToken } },
          );
          if (!deletion.ok && deletion.status !== 404) {
            await db.runTransaction(async tx => {
              const freshVideo = await tx.get(videoRef);
              if (freshVideo.exists && freshVideo.get("uploadStatus") === "deletion_pending") {
                tx.update(videoRef, { uploadStatus: "uploaded", updatedAt: FieldValue.serverTimestamp() });
              }
            });
            res.json({ ok: true, completed: true, deleted: false, deleteReason: "GOOGLE_DRIVE_DELETE_FAILED" }); return;
          }
          await db.runTransaction(async tx => {
            const [freshVideo, freshDownload] = await Promise.all([tx.get(videoRef), tx.get(downloadRef)]);
            if (!freshVideo.exists || !freshDownload.exists ||
                freshVideo.get("uploadStatus") !== "deletion_pending" ||
                freshDownload.get("status") !== "completed" ||
                freshDownload.get("transferVerified") !== true ||
                freshDownload.get("bytesTransferred") !== freshDownload.get("bytesExpected") ||
                !freshVideo.get("autoDeleteConsentAt")) {
              throw new Error("COMPLETION_OR_CONSENT_CHANGED");
            }
            tx.update(videoRef, {
              uploadStatus: "deleted", deletedAt: FieldValue.serverTimestamp(),
              googleDriveFileId: null, updatedAt: FieldValue.serverTimestamp(),
            });
            tx.create(db.collection("auditEvents").doc(), {
              actorUid: snap.get("customerUid"), orderId: snap.get("orderId"),
              eventType: "google_drive_video_auto_deleted_after_verified_download",
              eventData: { videoId: videoRef.id, downloadId, bytesTransferred: bytes },
              createdAt: FieldValue.serverTimestamp(),
            });
          });
          res.json({ ok: true, completed: true, deleted: true });
        } catch {
          // A transient token/network/Firestore failure must not strand the
          // video in deletion_pending. If Google actually deleted it despite a
          // lost response, a retry will receive 404 and safely finalize.
          await db.runTransaction(async tx => {
            const freshVideo = await tx.get(videoRef);
            if (freshVideo.exists && freshVideo.get("uploadStatus") === "deletion_pending") {
              tx.update(videoRef, { uploadStatus: "uploaded", updatedAt: FieldValue.serverTimestamp() });
            }
          }).catch(() => {});
          res.json({ ok: true, completed: true, deleted: false, deleteReason: "GOOGLE_DRIVE_DELETE_FAILED" });
        }
        return;
      }
      res.status(400).json({ error: "ACTION_NOT_SUPPORTED" });
    } catch (error) {
      res.status(500).json({ error: error instanceof Error ? error.message : "SHARE_WORKER_FAILED" });
    }
  },
);

export const weddingShareRedirect = onRequest({ region: "asia-south1" }, async (req, res) => {
  const token = String(req.query.token ?? "");
  if (req.method !== "GET" || !/^[a-f0-9]{64}$/.test(token)) {
    res.status(404).send("Invalid or expired share link."); return;
  }
  const found = await db.collection("shareLinks").where("tokenHash", "==", hash(token)).limit(1).get();
  if (found.empty || found.docs[0].get("isActive") !== true) {
    res.status(404).send("This share link is invalid or revoked."); return;
  }
  res.redirect(302, "https://wedding-video-download.weddingvideoshare-ym.workers.dev/?token=" + encodeURIComponent(token));
});
