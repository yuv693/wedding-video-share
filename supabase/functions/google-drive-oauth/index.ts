import { withSupabase } from "npm:@supabase/server@^1";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS, GET",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, "Content-Type": "application/json" },
});
const hex = (b: Uint8Array) => Array.from(b).map(x => x.toString(16).padStart(2, "0")).join("");
const sha256 = async (s: string) => hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))));
const randomHex = (n = 32) => {
  const b = new Uint8Array(n); crypto.getRandomValues(b); return hex(b);
};
const b64bytes = (s: string) => Uint8Array.from(atob(s), c => c.charCodeAt(0));

function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const secretRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SERVICE_ROLE_KEY");
  // Prefer the explicitly named service-role JWT for PostgREST RPC role resolution.
  // New sb_secret keys remain a fallback when the legacy key is unavailable.
  let key = legacy;
  if (!key && secretRaw) {
    try { key = JSON.parse(secretRaw)["default"]; } catch { /* handled below */ }
  }
  if (!url || !key) throw new Error("SUPABASE_BACKEND_KEY_MISSING");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

function oauthConfig() {
  const clientId = Deno.env.get("GOOGLE_CLIENT_ID");
  const clientSecret = Deno.env.get("GOOGLE_CLIENT_SECRET");
  const redirectUri = Deno.env.get("GOOGLE_REDIRECT_URI");
  const encryptionKey = Deno.env.get("GOOGLE_TOKEN_ENCRYPTION_KEY");
  if (!clientId || !clientSecret || !redirectUri || !encryptionKey) return null;
  return { clientId, clientSecret, redirectUri, encryptionKey };
}

async function encryptRefreshToken(token: string, keyB64: string): Promise<string> {
  const raw = b64bytes(keyB64);
  if (raw.length !== 32) throw new Error("GOOGLE_TOKEN_ENCRYPTION_KEY_MUST_BE_32_BYTE_BASE64");
  const key = await crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, ["encrypt"]);
  const iv = new Uint8Array(12); crypto.getRandomValues(iv);
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(token)));
  const combined = new Uint8Array(iv.length + ciphertext.length);
  combined.set(iv); combined.set(ciphertext, iv.length);
  return hex(combined);
}

async function startOAuth(req: Request, ctx: any) {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST_REQUIRED" }, 405);
  const cfg = oauthConfig();
  if (!cfg) return json({
    error: "GOOGLE_OAUTH_NOT_CONFIGURED",
    requiredSecrets: ["GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GOOGLE_REDIRECT_URI", "GOOGLE_TOKEN_ENCRYPTION_KEY"],
  }, 503);
  const state = randomHex(32);
  const stateHash = await sha256(state);
  // Use the same explicitly configured backend client as the OAuth callback.
  // The request's user identity still comes only from the validated user JWT.
  const customerId = ctx.userClaims?.id;
  if (typeof customerId !== "string" || !customerId) {
    console.error("OAUTH_USER_ID_MISSING");
    return json({ error: "OAUTH_USER_ID_MISSING" }, 401);
  }
  const admin = adminClient();
  const { error } = await admin.rpc("gdrive_oauth_state_create", {
    p_state_hash: stateHash,
    p_customer_id: customerId,
  });
  if (error) {
    console.error("OAUTH_STATE_SAVE_FAILED", error.code ?? "unknown", error.message ?? "no message");
    return json({ error: "OAUTH_STATE_SAVE_FAILED", code: error.code ?? null }, 500);
  }

  const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  authUrl.search = new URLSearchParams({
    client_id: cfg.clientId,
    redirect_uri: cfg.redirectUri,
    response_type: "code",
    scope: "openid email https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/drive.metadata.readonly",
    access_type: "offline",
    prompt: "select_account consent",
    include_granted_scopes: "true",
    state,
  }).toString();
  return json({ ok: true, authorizationUrl: authUrl.toString(), expiresInSeconds: 600 });
}

function htmlPage(title: string, message: string, success: boolean) {
  const target = success ? "weddingvideoshare://drive-connected?status=success" : "";
  if (success) return Response.redirect(target, 302);
  const color = success ? "#26734d" : "#8b263f";
  return new Response(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head><body style="font-family:Arial,sans-serif;background:#fffaf7;padding:32px;color:#29232a"><main style="max-width:440px;margin:12vh auto;background:white;padding:28px;border-radius:20px;box-shadow:0 8px 40px #0001"><h2 style="color:${color}">${title}</h2><p>${message}</p><p>You can close this page and return to Wedding Video Share.</p></main>${target ? `<script>setTimeout(()=>location.href='${target}',500)</script>` : ""}</body></html>`, {
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}

async function callback(req: Request) {
  const cfg = oauthConfig();
  if (!cfg) return htmlPage("Setup pending", "Google Drive connection is not configured yet. Please try again later.", false);
  const u = new URL(req.url);
  const state = u.searchParams.get("state") ?? "";
  const code = u.searchParams.get("code") ?? "";
  if (u.searchParams.get("error")) return htmlPage("Connection cancelled", "Google Drive permission was not granted.", false);
  if (!/^[a-f0-9]{64}$/.test(state) || !code) return htmlPage("Connection failed", "The Google authorization response was invalid.", false);

  const admin = adminClient();
  const { data: consumed, error: stateError } = await admin.rpc("gdrive_oauth_state_consume", {
    p_state_hash: await sha256(state),
  });
  const customerId = Array.isArray(consumed) && consumed.length === 1 ? consumed[0].customer_id : null;
  if (stateError || !customerId) return htmlPage("Connection expired", "This connection request expired or was already used. Please start again in the app.", false);

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: cfg.clientId,
      client_secret: cfg.clientSecret,
      redirect_uri: cfg.redirectUri,
      grant_type: "authorization_code",
    }),
  });
  const tokens = await tokenResponse.json();
  if (!tokenResponse.ok || typeof tokens.refresh_token !== "string") {
    console.error("GOOGLE_TOKEN_DIAGNOSTIC", JSON.stringify({
      http_status: tokenResponse.status,
      oauth_error: typeof tokens.error === "string" ? tokens.error : null,
      oauth_error_description: typeof tokens.error_description === "string" ? tokens.error_description.slice(0, 180) : null,
      refresh_token_present: typeof tokens.refresh_token === "string",
      access_token_present: typeof tokens.access_token === "string",
      granted_scope: typeof tokens.scope === "string" ? tokens.scope : null
    }));
    return htmlPage("Connection incomplete", "Google authorization returned without the offline token needed for a persistent Drive connection. Please try again later.", false);
  }

  const userResponse = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
    headers: { Authorization: `Bearer ${tokens.access_token}` },
  });
  const userInfo = await userResponse.json();
  if (!userResponse.ok || typeof userInfo.email !== "string") return htmlPage("Connection failed", "Could not verify the Google account email.", false);

  const cipherHex = await encryptRefreshToken(tokens.refresh_token, cfg.encryptionKey);
  const { error: saveError } = await admin.rpc("gdrive_connection_save", {
    p_customer_id: customerId,
    p_google_account_email: userInfo.email,
    p_refresh_token_cipher_hex: cipherHex,
  });
  if (saveError) return htmlPage("Connection not saved", "Google authorized access, but the secure connection could not be saved. Please contact support before retrying.", false);
  await admin.from("audit_events").insert({
    actor_user_id: customerId,
    event_type: "google_drive_connected",
    event_data: { google_account_email: userInfo.email, granted_scope: "drive.file" },
  });
  return htmlPage("Google Drive connected", `Your Google account (${userInfo.email}) is connected. You can return to Wedding Video Share.`, true);
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (url.pathname.endsWith("/callback") || (req.method === "GET" && url.searchParams.has("code"))) {
    try { return await callback(req); }
    catch { return htmlPage("Connection failed", "A server error occurred. No secret details were exposed. Please try again later.", false); }
  }
  const handler = withSupabase({ auth: "user" }, async (request, ctx) => {
    let body: Record<string, unknown>;
    try { body = await request.json(); } catch { return json({ error: "INVALID_JSON" }, 400); }
    if (body.action !== "start") return json({ error: "UNKNOWN_ACTION" }, 400);
    return startOAuth(request, ctx);
  });
  return handler(req);
});
