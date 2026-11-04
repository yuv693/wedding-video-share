import { withSupabase } from "npm:@supabase/server@^1";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  let key = Deno.env.get("SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!key && raw) { try { key = JSON.parse(raw)["default"]; } catch { /* fallback */ } }
  if (!url || !key) throw new Error("SERVER_CONFIGURATION_MISSING");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
function constantTimeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
async function hmacHex(secret: string, message: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return Array.from(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)))).map(x => x.toString(16).padStart(2, "0")).join("");
}
function config() {
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
  if (!keyId || !keySecret || !webhookSecret) throw new Error("RAZORPAY_NOT_CONFIGURED");
  return { keyId, keySecret, webhookSecret };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);

  if (url.pathname.endsWith("/webhook")) {
    if (req.method !== "POST") return json({ error: "POST_REQUIRED" }, 405);
    try {
      const cfg = config();
      const rawBody = await req.text();
      const signature = req.headers.get("x-razorpay-signature") ?? "";
      const expected = await hmacHex(cfg.webhookSecret, rawBody);
      if (!constantTimeEqual(signature.toLowerCase(), expected)) return json({ error: "INVALID_WEBHOOK_SIGNATURE" }, 401);
      const event = JSON.parse(rawBody);
      const admin = adminClient();
      if (event.event === "payment.captured") {
        const payment = event.payload?.payment?.entity;
        const gatewayOrderId = payment?.order_id;
        const paymentId = payment?.id;
        if (typeof gatewayOrderId !== "string" || typeof paymentId !== "string" || Number(payment.amount) !== 29000 || payment.currency !== "INR") return json({ error: "INVALID_PAYMENT_EVENT" }, 400);
        const { data: tx, error } = await admin.from("payment_transactions").select("id,order_id,customer_id,status").eq("gateway_order_id", gatewayOrderId).maybeSingle();
        if (error || !tx) return json({ error: "PAYMENT_ORDER_NOT_FOUND" }, 404);
        if (tx.status !== "verified") {
          const { error: txUpdateError } = await admin.from("payment_transactions").update({ status: "verified", gateway_payment_id: paymentId, verified_at: new Date().toISOString(), gateway_payload: { event: event.event, payment_id: paymentId } }).eq("id", tx.id);
          if (txUpdateError) return json({ error: "PAYMENT_RECORD_UPDATE_FAILED" }, 500);
          const { error: orderUpdateError } = await admin.from("wedding_orders").update({ payment_status: "paid", workflow_status: "video_ready_to_share" }).eq("id", tx.order_id).eq("customer_id", tx.customer_id);
          if (orderUpdateError) return json({ error: "ORDER_PAYMENT_UPDATE_FAILED" }, 500);
          await admin.from("audit_events").insert({ actor_user_id: tx.customer_id, order_id: tx.order_id, event_type: "payment_verified", event_data: { gateway: "razorpay", payment_id: paymentId, amount_paise: 29000 } });
        }
        return json({ ok: true, received: true });
      }
      if (event.event === "payment.failed") {
        const payment = event.payload?.payment?.entity;
        if (typeof payment?.order_id === "string") {
          const { data: tx } = await admin.from("payment_transactions").select("id,order_id,customer_id,status").eq("gateway_order_id", payment.order_id).maybeSingle();
          if (tx && tx.status !== "verified") {
            const { error: txUpdateError } = await admin.from("payment_transactions").update({ status: "failed", gateway_payment_id: payment.id ?? null, gateway_payload: { event: event.event } }).eq("id", tx.id);
            if (txUpdateError) return json({ error: "PAYMENT_RECORD_UPDATE_FAILED" }, 500);
            const { error: orderUpdateError } = await admin.from("wedding_orders").update({ payment_status: "failed" }).eq("id", tx.order_id).eq("customer_id", tx.customer_id).eq("payment_status", "pending");
            if (orderUpdateError) return json({ error: "ORDER_PAYMENT_UPDATE_FAILED" }, 500);
          }
        }
        return json({ ok: true, received: true });
      }
      return json({ ok: true, ignored: true });
    } catch (e) {
      const msg = e instanceof Error ? e.message : "";
      return json({ error: msg === "RAZORPAY_NOT_CONFIGURED" ? msg : "WEBHOOK_PROCESSING_FAILED" }, msg === "RAZORPAY_NOT_CONFIGURED" ? 503 : 400);
    }
  }

  if (req.method !== "POST") return json({ error: "POST_REQUIRED" }, 405);
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "INVALID_JSON" }, 400); }
  if (!["prepare_upload", "create_order"].includes(String(body.action ?? ""))) return json({ error: "ACTION_NOT_SUPPORTED" }, 400);

  const handler = withSupabase({ auth: "user" }, async (_request, ctx) => {
    try {
      const customerId = ctx.userClaims.sub;
      const admin = adminClient();
      const { data: authData, error: authError } = await admin.auth.admin.getUserById(customerId);
      if (authError || !authData.user?.email_confirmed_at) {
        if (authError) console.error("ACCOUNT_RECOVERY_LOOKUP_FAILED", authError.name, authError.status);
        return json({
          error: "ACCOUNT_RECOVERY_REQUIRED",
          note: "Verify a recovery email in Account before uploading or paying for this wedding.",
        }, 403);
      }
      let { data: order, error: orderError } = await admin.from("wedding_orders").select("id,payment_status,upload_locked").eq("customer_id", customerId).maybeSingle();
      if (orderError) throw new Error("ORDER_LOOKUP_FAILED");

      if (body.action === "prepare_upload") {
        if (order?.upload_locked) return json({ error: "ACCOUNT_ALREADY_USED", note: "This account has completed its one-video cycle. Create a new account for another wedding." }, 409);
        if (!order) {
          const created = await admin.from("wedding_orders").insert({
            customer_id: customerId, amount_paise: 29000, currency: "INR",
            payment_status: "pending", workflow_status: "payment_pending"
          }).select("id,payment_status,upload_locked").single();
          if (created.error || !created.data) throw new Error("ORDER_CREATE_FAILED");
          order = created.data;
        }
        return json({ ok: true, orderId: order.id, paymentStatus: order.payment_status });
      }

      if (!order) return json({ error: "VIDEO_REQUIRED", note: "Upload your wedding video before paying to share it." }, 409);
      if (order.upload_locked) return json({ error: "ACCOUNT_ALREADY_USED", note: "This account has completed its one-video cycle. A new wedding needs a new account." }, 409);
      const { data: uploadedVideo, error: videoError } = await admin.from("wedding_videos")
        .select("id,upload_status").eq("order_id", order.id).eq("customer_id", customerId).maybeSingle();
      if (videoError) throw new Error("VIDEO_LOOKUP_FAILED");
      if (!uploadedVideo || uploadedVideo.upload_status !== "uploaded") {
        return json({ error: "VIDEO_REQUIRED", note: "Upload and verify your wedding video before paying to share it." }, 409);
      }
      if (order.payment_status === "paid") return json({ error: "ALREADY_PAID", note: "Payment is already verified. Create your private share link." }, 409);
      const cfg = config();
      // Reuse a recent pending gateway order so repeated taps cannot create multiple payable orders.
      const { data: pendingTx, error: pendingTxError } = await admin.from("payment_transactions")
        .select("gateway_order_id,created_at")
        .eq("order_id", order.id)
        .eq("customer_id", customerId)
        .eq("gateway", "razorpay")
        .eq("status", "created")
        .not("gateway_order_id", "is", null)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (pendingTxError) throw new Error("PAYMENT_RECORD_LOOKUP_FAILED");
      if (pendingTx?.gateway_order_id) {
        return json({ ok: true, gateway: "razorpay", keyId: cfg.keyId, razorpayOrderId: pendingTx.gateway_order_id, orderId: order.id, amountPaise: 29000, currency: "INR", name: "Wedding Video Share", description: "One wedding video upload and share" });
      }

      const response = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: { "Authorization": "Basic " + btoa(cfg.keyId + ":" + cfg.keySecret), "Content-Type": "application/json" },
        body: JSON.stringify({ amount: 29000, currency: "INR", receipt: String(order.id), notes: { wedding_order_id: order.id, customer_id: customerId } }),
      });
      const gatewayOrder = await response.json();
      if (!response.ok || typeof gatewayOrder.id !== "string") throw new Error("RAZORPAY_ORDER_CREATE_FAILED");
      const { error: txError } = await admin.from("payment_transactions").insert({
        order_id: order.id, customer_id: customerId, gateway: "razorpay",
        gateway_order_id: gatewayOrder.id, amount_paise: 29000, currency: "INR", status: "created",
      });
      if (txError) throw new Error("PAYMENT_RECORD_CREATE_FAILED");
      return json({ ok: true, gateway: "razorpay", keyId: cfg.keyId, razorpayOrderId: gatewayOrder.id, orderId: order.id, amountPaise: 29000, currency: "INR", name: "Wedding Video Share", description: "One wedding video upload and share" });
    } catch (e) {
      const m = e instanceof Error ? e.message : "";
      console.error("RAZORPAY_CREATE_ORDER_FAILED", m || "UNKNOWN_ERROR");
      const known = ["RAZORPAY_NOT_CONFIGURED","ORDER_LOOKUP_FAILED","ORDER_CREATE_FAILED","VIDEO_LOOKUP_FAILED","RAZORPAY_ORDER_CREATE_FAILED","PAYMENT_RECORD_CREATE_FAILED","PAYMENT_RECORD_LOOKUP_FAILED"];
      const error = known.includes(m) ? m : "PAYMENT_SETUP_FAILED";
      return json({ error }, error === "RAZORPAY_NOT_CONFIGURED" ? 503 : 500);
    }
  });
  return handler(req);
});