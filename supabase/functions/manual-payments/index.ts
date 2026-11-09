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


function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function encodeJwtPart(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

async function firebaseAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = encodeJwtPart({ alg: "RS256", typ: "JWT" });
  const claims = encodeJwtPart({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  });
  const unsigned = header + "." + claims;
  const pem = serviceAccount.private_key.replace(/\\n/g, "\n");
  const encoded = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const binary = atob(encoded);
  const keyBytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  ));
  const assertion = unsigned + "." + base64Url(signature);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const result = await response.json();
  if (!response.ok || typeof result.access_token !== "string") {
    throw new Error("FIREBASE_OAUTH_FAILED: " + JSON.stringify(result).slice(0, 500));
  }
  return result.access_token;
}

async function notifyAdminPaymentEmail(): Promise<void> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("RESEND_FROM_EMAIL");
  if (!apiKey || !from) {
    console.log("ADMIN_EMAIL_NOTIFICATION_SKIPPED_MISSING_RESEND_SECRETS");
    return;
  }
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": "Bearer " + apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: ["ym6250067@gmail.com"],
      subject: "New wedding payment request — ₹290",
      text: "A customer has submitted a ₹290 payment request. Open Admin App to review.",
    }),
  });
  if (!response.ok) {
    const details = await response.text();
    throw new Error("RESEND_EMAIL_SEND_FAILED_" + response.status + ": " + details.slice(0, 300));
  }
  console.log("ADMIN_PAYMENT_EMAIL_SENT");
}

async function notifyAdminNewPayment(admin: ReturnType<typeof adminClient>): Promise<void> {
  const raw = Deno.env.get("FIREBASE_FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("FIREBASE_FCM_SERVICE_ACCOUNT_JSON secret is missing");
  const serviceAccount = JSON.parse(raw) as Record<string, string>;
  if (!serviceAccount.project_id || !serviceAccount.client_email || !serviceAccount.private_key) {
    throw new Error("Firebase service account JSON is incomplete");
  }
  const { data: devices, error } = await admin.from("admin_fcm_tokens")
    .select("id,fcm_token")
    .eq("platform", "android");
  if (error) throw new Error("FCM_TOKEN_LOOKUP_FAILED: " + error.message);
  if (!devices || devices.length === 0) {
    console.log("FCM_SKIP_NO_ADMIN_DEVICE_TOKENS");
    return;
  }
  const accessToken = await firebaseAccessToken(serviceAccount);
  const url = "https://fcm.googleapis.com/v1/projects/" + serviceAccount.project_id + "/messages:send";
  const results = await Promise.allSettled(devices.map(async (device) => {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + accessToken,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: device.fcm_token,
          notification: {
            title: "New wedding payment request",
            body: "A customer has submitted a ₹290 payment request. Open Admin App to review.",
          },
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "payment_requests",
              sound: "default",
              default_sound: true,
            },
          },
          data: { type: "new_payment_request" },
        },
      }),
    });
    if (!response.ok) {
      const details = await response.text();
      throw new Error("FCM_SEND_FAILED_" + response.status + ": " + details.slice(0, 300));
    }
  }));
  const failures = results.filter((result) => result.status === "rejected");
  if (failures.length) {
    console.error("FCM_SEND_PARTIAL_FAILURE", failures.map((item) =>
      item.status === "rejected" ? String(item.reason) : ""
    ));
  }
  console.log("FCM_PAYMENT_ALERTS_SENT", results.length - failures.length, "of", devices.length);
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
      let { data: order, error: orderError } = await admin.from("wedding_orders")
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

      const { data: videos, error: videoError } = await admin.from("wedding_videos")
        .select("id,upload_status")
        .eq("order_id", order.id)
        .eq("customer_id", customerId)
        .eq("upload_status", "uploaded")
        .is("deleted_at", null);
      if (videoError) return json({ error: "VIDEO_LOOKUP_FAILED" }, 500);
      if (!videos || videos.length === 0) {
        return json({ error: "VIDEO_REQUIRED", note: "Upload at least one wedding video before submitting payment." }, 409);
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
      try {
        await notifyAdminNewPayment(admin);
      } catch (notificationError) {
        console.error("ADMIN_FCM_NOTIFICATION_FAILED", notificationError instanceof Error ? notificationError.message : "UNKNOWN");
      }
      try {
        await notifyAdminPaymentEmail();
      } catch (emailError) {
        console.error("ADMIN_EMAIL_NOTIFICATION_FAILED", emailError instanceof Error ? emailError.message : "UNKNOWN");
      }
      return json({ ok: true, status: "pending", note: "Payment request submitted. Sharing unlocks after manual verification." });
    } catch (error) {
      console.error("MANUAL_PAYMENT_ERROR", error instanceof Error ? error.message : "UNKNOWN");
      return json({ error: "MANUAL_PAYMENT_FAILED" }, 500);
    }
  });
  return handler(req);
});
