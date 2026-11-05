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
      const customerId = ctx.userClaims?.sub;
      if (typeof customerId !== "string" || !customerId) return json({ error: "AUTH_REQUIRED" }, 401);
      const admin = adminClient();
      const { data: order, error: orderError } = await admin.from("wedding_orders")
        .select("id,payment_status,upload_locked")
        .eq("customer_id", customerId)
        .maybeSingle();
      if (orderError) return json({ error: "ORDER_LOOKUP_FAILED" }, 500);
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

      const utr = String(body.utr ?? "").trim().toUpperCase();
      if (!/^[A-Z0-9]{8,32}$/.test(utr)) return json({ error: "INVALID_UTR", note: "Enter a valid UPI transaction ID / UTR." }, 400);

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
        .select("id,status,gateway_payment_id")
        .eq("order_id", order.id)
        .eq("customer_id", customerId)
        .eq("gateway", "manual_upi")
        .eq("status", "pending")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (existingError) return json({ error: "PAYMENT_LOOKUP_FAILED" }, 500);

      if (existing) {
        if (existing.gateway_payment_id === utr) return json({ ok: true, status: "pending", note: "This UTR is already submitted for verification." });
        const { error } = await admin.from("payment_transactions")
          .update({ gateway_payment_id: utr, gateway_payload: { method: "upi_qr", submitted_at: new Date().toISOString() } })
          .eq("id", existing.id)
          .eq("status", "pending");
        if (error) return json({ error: "PAYMENT_SUBMISSION_FAILED", note: "Could not update the submitted UTR." }, 500);
        return json({ ok: true, status: "pending", note: "Updated UTR submitted for manual verification." });
      }

      const { error: insertError } = await admin.from("payment_transactions").insert({
        order_id: order.id,
        customer_id: customerId,
        gateway: "manual_upi",
        gateway_payment_id: utr,
        amount_paise: 29000,
        currency: "INR",
        status: "pending",
        gateway_payload: { method: "upi_qr", submitted_at: new Date().toISOString() },
      });
      if (insertError) {
        console.error("MANUAL_PAYMENT_INSERT_FAILED", insertError.message);
        return json({ error: "PAYMENT_SUBMISSION_FAILED", note: "This UTR may already have been used. Check it and try again." }, 409);
      }
      await admin.from("audit_events").insert({
        actor_user_id: customerId,
        order_id: order.id,
        event_type: "manual_upi_payment_submitted",
        event_data: { amount_paise: 29000, gateway: "manual_upi" },
      });
      return json({ ok: true, status: "pending", note: "Payment details submitted. Sharing unlocks after manual verification." });
    } catch (error) {
      console.error("MANUAL_PAYMENT_ERROR", error instanceof Error ? error.message : "UNKNOWN");
      return json({ error: "MANUAL_PAYMENT_FAILED" }, 500);
    }
  });
  return handler(req);
});
