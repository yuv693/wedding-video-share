import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
export { createRazorpayOrder, verifyRazorpayPayment, razorpayWebhook } from "./payments";

if (!getApps().length) initializeApp();
setGlobalOptions({ region: "asia-south1" });
const db = getFirestore();

function wire(value: any): any {
  if (value == null) return value;
  if (typeof value?.toDate === 'function') return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(wire);
  if (typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, wire(item)]));
  return value;
}

function requireUid(request: { auth?: { uid: string } | null }): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please sign in to continue.");
  return uid;
}

export const bootstrapCustomer = onCall(async (request) => {
  const uid = requireUid(request);
  const userRef = db.collection("customers").doc(uid);
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(userRef);
    if (!snapshot.exists) {
      tx.create(userRef, {
        uid,
        email: request.auth?.token.email ?? null,
        displayName: request.auth?.token.name ?? null,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      tx.set(userRef, {
        email: request.auth?.token.email ?? snapshot.get("email") ?? null,
        displayName: request.auth?.token.name ?? snapshot.get("displayName") ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  });
  return { ok: true, customerUid: uid };
});

export const prepareWeddingUpload = onCall(async (request) => {
  const uid = requireUid(request);
  const orderRef = db.collection("weddingOrders").doc(uid);
  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(orderRef);
    if (snapshot.exists && snapshot.get("uploadLocked") === true) {
      throw new HttpsError("failed-precondition", "This account has already used its one wedding video slot.");
    }
    if (!snapshot.exists) {
      tx.create(orderRef, {
        customerUid: uid,
        amountPaise: 29000,
        currency: "INR",
        paymentStatus: "pending",
        workflowStatus: "upload_pending",
        uploadLocked: false,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    return { ok: true, orderId: uid, paymentStatus: snapshot.exists ? snapshot.get("paymentStatus") : "pending" };
  });
});

export const getWeddingAccountState = onCall(async (request) => {
  const uid = requireUid(request);
  const [order, videos, notifications] = await Promise.all([
    db.collection("weddingOrders").doc(uid).get(),
    db.collection("weddingVideos").where("customerUid", "==", uid).limit(1).get(),
    db.collection("customerNotifications").where("customerUid", "==", uid)
      .orderBy("createdAt", "desc").limit(5).get(),
  ]);
  return {
    order: order.exists ? wire(order.data()) : null,
    video: videos.empty ? null : wire({ id: videos.docs[0].id, ...videos.docs[0].data() }),
    notifications: notifications.docs.map((doc) => wire({ id: doc.id, ...doc.data() })),
  };
});

export const setAutoDeleteConsent = onCall(async (request) => {
  const uid = requireUid(request);
  const videoId = String(request.data?.videoId ?? "");
  const consent = request.data?.consent;
  if (!videoId || typeof consent !== "boolean") {
    throw new HttpsError("invalid-argument", "A video and consent choice are required.");
  }
  const videoRef = db.collection("weddingVideos").doc(videoId);
  await db.runTransaction(async (tx) => {
    const video = await tx.get(videoRef);
    if (!video.exists || video.get("customerUid") !== uid) {
      throw new HttpsError("not-found", "Video not found.");
    }
    if (video.get("uploadStatus") !== "uploaded" || video.get("deletedAt")) {
      throw new HttpsError("failed-precondition", "Consent can only be changed for an uploaded video.");
    }
    tx.update(videoRef, {
      autoDeleteConsentAt: consent ? FieldValue.serverTimestamp() : null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const auditRef = db.collection("auditEvents").doc();
    tx.create(auditRef, {
      actorUid: uid,
      orderId: uid,
      eventType: consent ? "auto_delete_consent_granted" : "auto_delete_consent_withdrawn",
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { ok: true, consent };
});
