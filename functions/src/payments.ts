import { createHmac, timingSafeEqual } from "node:crypto";
import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";

if (!getApps().length) initializeApp();
const db = getFirestore();
const razorpayKeyId = defineSecret("RAZORPAY_KEY_ID");
const razorpayKeySecret = defineSecret("RAZORPAY_KEY_SECRET");
const razorpayWebhookSecret = defineSecret("RAZORPAY_WEBHOOK_SECRET");
const PRICE_PAISE = 29000;
const CURRENCY = "INR";

function uidOf(request: { auth?: { uid: string } | null }): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please sign in to continue.");
  return uid;
}
function signatureMatches(expected: string, supplied: string): boolean {
  const a = Buffer.from(expected, "hex");
  const b = Buffer.from(supplied, "hex");
  return a.length === b.length && a.length > 0 && timingSafeEqual(a, b);
}
function hmac(secret: string, value: string): string {
  return createHmac("sha256", secret).update(value).digest("hex");
}
async function razorpayGetPayment(paymentId: string, keyId: string, keySecret: string) {
  const response = await fetch("https://api.razorpay.com/v1/payments/" + encodeURIComponent(paymentId), {
    headers: { Authorization: "Basic " + Buffer.from(keyId + ":" + keySecret).toString("base64") },
  });
  const payment = await response.json() as Record<string, any>;
  if (!response.ok) throw new HttpsError("unavailable", "Payment status could not be confirmed with Razorpay.");
  return payment;
}
async function markPaymentPaid(uid: string, gatewayOrderId: string, paymentId: string, payment: Record<string, any>) {
  const txRef = db.collection("paymentTransactions").doc(gatewayOrderId);
  const orderRef = db.collection("weddingOrders").doc(uid);
  await db.runTransaction(async (transaction) => {
    const txSnap = await transaction.get(txRef);
    const orderSnap = await transaction.get(orderRef);
    const videoSnap = await transaction.get(db.collection("weddingVideos").doc(uid));
    if (!txSnap.exists || txSnap.get("customerUid") !== uid) {
      throw new HttpsError("not-found", "Payment order was not found for this account.");
    }
    if (!orderSnap.exists || orderSnap.get("customerUid") !== uid) {
      throw new HttpsError("failed-precondition", "Wedding order was not found.");
    }
    if (txSnap.get("amountPaise") !== PRICE_PAISE || txSnap.get("currency") !== CURRENCY ||
        txSnap.get("gateway") !== "razorpay") {
      throw new HttpsError("failed-precondition", "Payment amount or currency does not match.");
    }
    if (!videoSnap.exists || videoSnap.get("customerUid") !== uid ||
        videoSnap.get("uploadStatus") !== "uploaded" ||
        !videoSnap.get("autoDeleteConsentAt") ||
        orderSnap.get("uploadLocked") !== true) {
      throw new HttpsError("failed-precondition", "Verified video upload and active Drive deletion consent are required before payment can be marked paid.");
    }
    if (txSnap.get("status") === "verified") return;
    transaction.update(txRef, {
      status: "verified",
      gatewayPaymentId: paymentId,
      verifiedAt: FieldValue.serverTimestamp(),
      gatewayPayload: { status: payment.status, amount: payment.amount, currency: payment.currency },
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(orderRef, {
      paymentStatus: "paid",
      workflowStatus: "video_ready_to_share",
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(db.collection("auditEvents").doc(), {
      actorUid: uid,
      orderId: uid,
      eventType: "payment_verified",
      eventData: { gateway: "razorpay", paymentId, amountPaise: PRICE_PAISE },
      createdAt: FieldValue.serverTimestamp(),
    });
  });
}

export const createRazorpayOrder = onCall(
  { secrets: [razorpayKeyId, razorpayKeySecret] },
  async (request) => {
    const uid = uidOf(request);
    const [orderSnap, videoQuery] = await Promise.all([
      db.collection("weddingOrders").doc(uid).get(),
      db.collection("weddingVideos").where("customerUid", "==", uid).limit(1).get(),
    ]);
    if (!orderSnap.exists || orderSnap.get("customerUid") !== uid) {
      throw new HttpsError("failed-precondition", "Prepare your wedding upload first.");
    }
    // The one-video slot is locked by the server after the upload is
    // verified. That lock is expected here; it prevents another upload while
    // allowing this already-uploaded video to be paid for and shared.
    if (orderSnap.get("uploadLocked") !== true) {
      throw new HttpsError("failed-precondition", "The wedding video upload has not been verified yet.");
    }
    if (orderSnap.get("paymentStatus") === "paid") {
      throw new HttpsError("already-exists", "Payment is already verified.");
    }
    if (videoQuery.empty || videoQuery.docs[0].get("uploadStatus") !== "uploaded") {
      throw new HttpsError("failed-precondition", "Upload and verify your wedding video before payment.");
    }
    if (!videoQuery.docs[0].get("autoDeleteConsentAt")) {
      throw new HttpsError("failed-precondition", "Confirm automatic Google Drive deletion after the receiver's full verified download before payment.");
    }
    const existing = await db.collection("paymentTransactions")
      .where("customerUid", "==", uid).limit(10).get();
    const keyId = razorpayKeyId.value();
    const keySecret = razorpayKeySecret.value();
    const previous = existing.docs
      .filter((doc) => doc.get("status") === "created")
      .sort((a, b) => (b.get("createdAt")?.toMillis?.() ?? 0) - (a.get("createdAt")?.toMillis?.() ?? 0))[0];
    if (previous) {
      const createdAt = previous.get("createdAt")?.toDate?.()?.getTime?.() ?? 0;
      if (Date.now() - createdAt < 30 * 60 * 1000 && previous.get("gatewayOrderId")) {
        return {
          ok: true, gateway: "razorpay", keyId,
          razorpayOrderId: previous.get("gatewayOrderId"),
          orderId: uid, amountPaise: PRICE_PAISE, currency: CURRENCY,
          name: "Wedding Video Share", description: "One wedding video upload and share",
        };
      }
    }
    const response = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        Authorization: "Basic " + Buffer.from(keyId + ":" + keySecret).toString("base64"),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: PRICE_PAISE, currency: CURRENCY, receipt: uid,
        notes: { wedding_order_id: uid, customer_uid: uid },
      }),
    });
    const gatewayOrder = await response.json() as Record<string, any>;
    if (!response.ok || typeof gatewayOrder.id !== "string" ||
        gatewayOrder.amount !== PRICE_PAISE || gatewayOrder.currency !== CURRENCY) {
      throw new HttpsError("unavailable", "Razorpay could not create the payment order.");
    }
    const txRef = db.collection("paymentTransactions").doc(gatewayOrder.id);
    await txRef.create({
      customerUid: uid, orderId: uid, gateway: "razorpay",
      gatewayOrderId: gatewayOrder.id, amountPaise: PRICE_PAISE,
      currency: CURRENCY, status: "created",
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      ok: true, gateway: "razorpay", keyId, razorpayOrderId: gatewayOrder.id,
      orderId: uid, amountPaise: PRICE_PAISE, currency: CURRENCY,
      name: "Wedding Video Share", description: "One wedding video upload and share",
    };
  },
);

export const verifyRazorpayPayment = onCall(
  { secrets: [razorpayKeyId, razorpayKeySecret] },
  async (request) => {
    const uid = uidOf(request);
    const gatewayOrderId = String(request.data?.razorpayOrderId ?? "");
    const paymentId = String(request.data?.razorpayPaymentId ?? "");
    const suppliedSignature = String(request.data?.razorpaySignature ?? "");
    if (!gatewayOrderId || !paymentId || !/^[a-f0-9]{64}$/i.test(suppliedSignature)) {
      throw new HttpsError("invalid-argument", "Payment verification details are incomplete.");
    }
    const txSnap = await db.collection("paymentTransactions").doc(gatewayOrderId).get();
    if (!txSnap.exists || txSnap.get("customerUid") !== uid) {
      throw new HttpsError("not-found", "Payment order does not belong to this account.");
    }
    const expected = hmac(razorpayKeySecret.value(), gatewayOrderId + "|" + paymentId);
    if (!signatureMatches(expected, suppliedSignature)) {
      throw new HttpsError("permission-denied", "Razorpay payment signature is invalid.");
    }
    const payment = await razorpayGetPayment(paymentId, razorpayKeyId.value(), razorpayKeySecret.value());
    if (payment.order_id !== gatewayOrderId || payment.amount !== PRICE_PAISE ||
        payment.currency !== CURRENCY || payment.status !== "captured") {
      throw new HttpsError("failed-precondition", "Razorpay has not confirmed a captured ₹290 payment.");
    }
    await markPaymentPaid(uid, gatewayOrderId, paymentId, payment);
    return { ok: true, verified: true, paymentStatus: "paid" };
  },
);

export const razorpayWebhook = onRequest(
  { secrets: [razorpayKeyId, razorpayKeySecret, razorpayWebhookSecret] },
  async (request, response) => {
    if (request.method !== "POST") { response.status(405).send("POST required"); return; }
    const signature = String(request.headers["x-razorpay-signature"] ?? "");
    const raw = request.rawBody?.toString("utf8") ?? "";
    if (!raw || !/^[a-f0-9]{64}$/i.test(signature) ||
        !signatureMatches(hmac(razorpayWebhookSecret.value(), raw), signature)) {
      response.status(401).send("Invalid webhook signature"); return;
    }
    const eventId = String(request.headers["x-razorpay-event-id"] ?? "");
    const event = JSON.parse(raw) as Record<string, any>;
    const eventRef = eventId ? db.collection("webhookEvents").doc(eventId) : null;
    if (eventRef) {
      const seen = await eventRef.get();
      if (seen.exists) { response.status(200).json({ ok: true, duplicate: true }); return; }
    }
    try {
      if (event.event === "payment.captured") {
        const payment = event.payload?.payment?.entity;
        const gatewayOrderId = payment?.order_id;
        const paymentId = payment?.id;
        if (typeof gatewayOrderId !== "string" || typeof paymentId !== "string" ||
            payment.amount !== PRICE_PAISE || payment.currency !== CURRENCY || payment.status !== "captured") {
          response.status(400).json({ error: "Invalid payment event" }); return;
        }
        const txSnap = await db.collection("paymentTransactions").doc(gatewayOrderId).get();
        if (!txSnap.exists) { response.status(404).json({ error: "Payment order not found" }); return; }
        await markPaymentPaid(txSnap.get("customerUid"), gatewayOrderId, paymentId, payment);
      }
      if (eventRef) await eventRef.create({
        eventType: event.event ?? "unknown", processedAt: FieldValue.serverTimestamp(),
      });
      response.status(200).json({ ok: true, received: true });
    } catch (error) {
      // Razorpay may retry or deliver the same event concurrently. Payment
      // verification is transactional and idempotent; if another invocation
      // already recorded this event, acknowledge the duplicate instead of
      // returning 500 and causing an endless retry loop.
      if (eventRef) {
        const recorded = await eventRef.get().catch(() => null);
        if (recorded?.exists) {
          response.status(200).json({ ok: true, duplicate: true });
          return;
        }
      }
      console.error("Razorpay webhook processing failed", error);
      response.status(500).json({ error: "Webhook processing failed" });
    }
  },
);
