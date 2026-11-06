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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST_REQUIRED" }, 405);
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "INVALID_JSON" }, 400); }

  const handler = withSupabase({ auth: "user" }, async (_request, ctx) => {
    try {
      const customerId = ctx.userClaims?.id;
      if (typeof customerId !== "string" || !customerId) return json({ error: "AUTH_REQUIRED" }, 401);
      const admin = adminClient();
      const { data: order, error: orderError } = await admin.from("wedding_orders")
        .select("id,payment_status,upload_locked")
        .eq("customer_id", customerId)
        .maybeSingle();
      if (orderError) return json({ error: "ORDER_LOOKUP_FAILED" }, 500);

      // Paytm QR uses manual verification; prepare the customer order without contacting Razorpay.
      if (body.action === "prepare_upload") {
        if (order?.upload_locked) return json({ error: "ACCOUNT_ALREADY_USED", note: "This account has completed its one-video cycle. Create a new account for another wedding." }, 409);
        if (!order) {
          const { data: created, error: createError } = await admin.from("wedding_orders").insert({
            customer_id: customerId,
            amount_paise: 29000,
            currency: "INR",
            payment_status: "pending",
            workflow_status: "payment_pending",
          }).select("id,payment_status,upload_locked").single();
          if (createError || !created) {
            console.error("MANUAL_ORDER_CREATE_FAILED", createError?.message ?? "NO_ROW_RETURNED");
            return json({ error: "ORDER_CREATE_FAILED" }, 500);
          }
          order = created;
        }
        return json({ ok: true, orderId: order.id, paymentStatus: order.payment_status });
      }
      if (!order) return json({ error: "ORDER_NOT_FOUND" }, 404);

      if (body.action === "status") {
        const { data: tx, error } = await admin.from("payment_transactions")
          .select("status,created_at")
          .eq("order_id", order.id)
          .eq("customer_id", customerId)
          .eq("gateway", "manual_upi")
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (error) return json({ error: "PAYMENT_STATUS_LOOKUP_FAILED" }, 500);
        return json({ ok: true, status: order.payment_status === "paid" ? "verified" : tx?.status ?? null });
      }

      if (body.action !== "submit") return json({ error: "ACTION_NOT_SUPPORTED" }, 400);
      if (order.payment_status === "paid") return json({ ok: true, status: "verified", note: "Payment is already verified." });
      if (order.upload_locked) return json({ error: "ACCOUNT_ALREADY_USED" }, 409);

      const { data: video, error: videoError } = await admin.from("wedding_videos")
        .select("id,upload_status")
        .eq("order_id", order.id)
        .eq("customer_id", customerId)
        .maybeSingle();
      if (videoError) return json({ error: "VIDEO_LOOKUP_FAILED" }, 500);
      if (!video || video.upload_status !== "uploaded") {
        return json({ error: "VIDEO_REQUIRED", note: "Upload your wedding video before submitting payment." }, 409);
      }

      const { data: existing, error: existingError } = await admin.from("payment_transactions")
        .select("id,status")
        .eq("order_id", order.id)
        .eq("customer_id", customerId)
        .eq("gateway", "manual_upi")
        .eq("status", "pending")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (existingError) return json({ error: "PAYMENT_LOOKUP_FAILED" }, 500);

      if (existing) {
        return json({ ok: true, status: "pending", note: "Your payment request is already waiting for manual verification." });
      }

      const { error: insertError } = await admin.from("payment_transactions").insert({
        order_id: order.id,
        customer_id: customerId,
        gateway: "manual_upi",
        amount_paise: 29000,
        currency: "INR",
        status: "pending",
        gateway_payload: { method: "upi_qr", submitted_at: new Date().toISOString() },
      });
      if (insertError) {
        console.error("MANUAL_PAYMENT_INSERT_FAILED", insertError.message);
        return json({ error: "PAYMENT_SUBMISSION_FAILED", note: "Could not submit your payment request. Please refresh and try again." }, 500);
      }
      await admin.from("audit_events").insert({
        actor_user_id: customerId,
        order_id: order.id,
        event_type: "manual_upi_payment_requested",
        event_data: { amount_paise: 29000, gateway: "manual_upi", method: "qr_confirmation_only" },
      });
      return json({ ok: true, status: "pending", note: "Payment request submitted. Sharing unlocks after manual verification." });
    } catch (error) {
      console.error("MANUAL_PAYMENT_ERROR", error instanceof Error ? error.message : "UNKNOWN");
      return json({ error: "MANUAL_PAYMENT_FAILED" }, 500);
    }
  });
  return handler(req);
});
