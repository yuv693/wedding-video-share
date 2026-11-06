import { withSupabase } from "npm:@supabase/server@^1";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
const MAX_BYTES = 40000000000;
const hexToBytes = (hex: string) => Uint8Array.from((hex.match(/.{1,2}/g) ?? []).map(x => parseInt(x, 16)));
const bytesToHex = (b: Uint8Array) => Array.from(b).map(x => x.toString(16).padStart(2, "0")).join("");
const b64bytes = (s: string) => Uint8Array.from(atob(s), c => c.charCodeAt(0));

function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const secretRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
  let key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
  if (!key && secretRaw) { try { key = JSON.parse(secretRaw)["default"]; } catch { /* fallback */ } }
  if (!url || !key) throw new Error("SUPABASE_BACKEND_KEY_MISSING");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

async function googleConfig() {
  const clientId = Deno.env.get("GOOGLE_CLIENT_ID");
  const clientSecret = Deno.env.get("GOOGLE_CLIENT_SECRET");
  const encryptionKey = Deno.env.get("GOOGLE_TOKEN_ENCRYPTION_KEY");
  if (!clientId || !clientSecret || !encryptionKey) throw new Error("GOOGLE_OAUTH_NOT_CONFIGURED");
  return { clientId, clientSecret, encryptionKey };
}

async function getGoogleAccessToken(admin: any, customerId: string) {
  const cfg = await googleConfig();
  const { data, error } = await admin.rpc("gdrive_connection_get", { p_customer_id: customerId });
  const row = Array.isArray(data) ? data[0] : null;
  if (error || !row?.encrypted_refresh_token_hex) throw new Error("GOOGLE_DRIVE_NOT_CONNECTED");
  const raw = b64bytes(cfg.encryptionKey);
  if (raw.length !== 32) throw new Error("GOOGLE_TOKEN_ENCRYPTION_KEY_MUST_BE_32_BYTE_BASE64");
  const combined = hexToBytes(row.encrypted_refresh_token_hex);
  if (combined.length < 29) throw new Error("GOOGLE_REFRESH_TOKEN_CIPHERTEXT_INVALID");
  const key = await crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, ["decrypt"]);
  const iv = combined.slice(0, 12);
  const cipher = combined.slice(12);
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, cipher);
  const refreshToken = new TextDecoder().decode(plain);
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: cfg.clientId, client_secret: cfg.clientSecret, refresh_token: refreshToken, grant_type: "refresh_token" }),
  });
  const tokenData = await tokenResponse.json();
  if (!tokenResponse.ok || typeof tokenData.access_token !== "string") {
    console.error("GOOGLE_TOKEN_REFRESH_ERROR", JSON.stringify({
      http_status: tokenResponse.status,
      oauth_error: typeof tokenData.error === "string" ? tokenData.error : null,
      oauth_error_description: typeof tokenData.error_description === "string" ? tokenData.error_description.slice(0, 180) : null,
      access_token_present: typeof tokenData.access_token === "string",
    }));
    throw new Error("GOOGLE_ACCESS_TOKEN_REFRESH_FAILED");
  }
  return { accessToken: tokenData.access_token as string, email: row.google_account_email as string, folderId: row.google_drive_folder_id as string | null };
}

function googleApiDiagnostic(label: string, status: number, data: any) {
  const apiError = data?.error;
  const first = Array.isArray(apiError?.errors) ? apiError.errors[0] : null;
  console.error("GOOGLE_DRIVE_API_ERROR", JSON.stringify({
    operation: label,
    http_status: status,
    code: typeof apiError?.code === "number" ? apiError.code : null,
    status: typeof apiError?.status === "string" ? apiError.status : null,
    reason: typeof first?.reason === "string" ? first.reason : null,
    message: typeof apiError?.message === "string" ? apiError.message.slice(0, 240) : null,
  }));
}

async function driveRequest(url: string, accessToken: string, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("Authorization", "Bearer " + accessToken);
  return await fetch(url, { ...init, headers });
}

async function ensureFolder(admin: any, customerId: string, accessToken: string, existing: string | null) {
  if (existing) return existing;
  const res = await driveRequest("https://www.googleapis.com/drive/v3/files?fields=id,name,mimeType", accessToken, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name: "Wedding Video Share", mimeType: "application/vnd.google-apps.folder" }),
  });
  const data = await res.json();
  if (!res.ok || typeof data.id !== "string") throw new Error("GOOGLE_DRIVE_FOLDER_CREATE_FAILED");
  const { data: saved, error } = await admin.rpc("gdrive_connection_set_folder", { p_customer_id: customerId, p_folder_id: data.id });
  if (error || saved !== true) throw new Error("GOOGLE_DRIVE_FOLDER_SAVE_FAILED");
  return data.id as string;
}

function parseError(e: unknown) {
  const msg = e instanceof Error ? e.message : "INTERNAL_ERROR";
  const known = new Set([
    "GOOGLE_OAUTH_NOT_CONFIGURED", "GOOGLE_DRIVE_NOT_CONNECTED",
    "GOOGLE_TOKEN_ENCRYPTION_KEY_MUST_BE_32_BYTE_BASE64", "GOOGLE_REFRESH_TOKEN_CIPHERTEXT_INVALID",
    "GOOGLE_ACCESS_TOKEN_REFRESH_FAILED", "GOOGLE_DRIVE_FOLDER_CREATE_FAILED",
    "GOOGLE_DRIVE_FOLDER_SAVE_FAILED", "ORDER_NOT_FOUND", "PAYMENT_REQUIRED",
    "UPLOAD_LOCKED", "VIDEO_ALREADY_EXISTS", "VIDEO_LOOKUP_FAILED", "FILE_SIZE_INVALID", "INSUFFICIENT_DRIVE_SPACE",
    "DRIVE_QUOTA_UNAVAILABLE", "UPLOAD_SESSION_CREATE_FAILED", "UPLOAD_SESSION_SAVE_FAILED",
    "UPLOAD_SESSION_NOT_FOUND", "UPLOAD_SESSION_LOOKUP_FAILED", "DRIVE_FILE_NOT_VERIFIED", "VIDEO_RECORD_SAVE_FAILED",
    "VIDEO_NOT_FOUND", "GOOGLE_DRIVE_DELETE_FAILED", "ACTION_NOT_SUPPORTED"
  ]);
  return known.has(msg) ? msg : "INTERNAL_ERROR";
}

Deno.serve((req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const handler = withSupabase({ auth: "user" }, async (request, ctx) => {
    try {
      const body = await request.json();
      const customerId = ctx.userClaims?.id;
      if (typeof customerId !== "string" || !customerId) {
        console.error("STORAGE_USER_ID_MISSING");
        return json({ ok: false, error: "AUTH_USER_ID_MISSING" }, 401);
      }
      const admin = adminClient();
      const { accessToken, email, folderId: existingFolder } = await getGoogleAccessToken(admin, customerId);

      if (body.action === "set_auto_delete_consent") {
        const videoId = String(body.videoId ?? "");
        const consent = body.consent === true;
        if (!videoId) throw new Error("VIDEO_NOT_FOUND");
        const { data: video, error } = await admin.from("wedding_videos")
          .update({ auto_delete_consent_at: consent ? new Date().toISOString() : null })
          .eq("id", videoId).eq("customer_id", customerId)
          .eq("upload_status", "uploaded").is("deleted_at", null)
          .select("id").maybeSingle();
        if (error || !video) throw new Error("VIDEO_NOT_FOUND");
        await admin.from("audit_events").insert({
          actor_user_id: customerId,
          event_type: consent ? "automatic_drive_deletion_consent_granted" : "automatic_drive_deletion_consent_revoked",
          event_data: { video_id: videoId }
        });
        return json({ ok: true, consent });
      }

      if (body.action === "resume_upload") {
        const orderId = String(body.orderId ?? "");
        if (!orderId) throw new Error("ORDER_NOT_FOUND");
        const { data: order, error: orderError } = await admin.from("wedding_orders").select("id,customer_id,payment_status,upload_locked").eq("id", orderId).eq("customer_id", customerId).maybeSingle();
        if (orderError || !order) throw new Error("ORDER_NOT_FOUND");
        if (order.upload_locked) throw new Error("UPLOAD_LOCKED");
        const { data: sessions, error: sessionError } = await admin.rpc("gdrive_upload_session_get", { p_order_id: orderId, p_customer_id: customerId });
        const session = Array.isArray(sessions) ? sessions[0] : null;
        if (sessionError) throw new Error("UPLOAD_SESSION_LOOKUP_FAILED");
        if (!session) return json({ ok: false, error: "UPLOAD_SESSION_NOT_FOUND" });
        return json({ ok: true, resumed: true, uploadUrl: session.session_uri, expectedSizeBytes: Number(session.expected_size_bytes), filename: session.original_filename, mimeType: session.mime_type, chunkSizeBytes: 8388608 });
      }

      if (body.action === "quota") {
        const res = await driveRequest("https://www.googleapis.com/drive/v3/about?fields=user(emailAddress),storageQuota(limit,usage,usageInDrive,usageInDriveTrash)", accessToken);
        const data = await res.json();
        if (!res.ok || !data.storageQuota) { googleApiDiagnostic("quota", res.status, data); throw new Error("DRIVE_QUOTA_UNAVAILABLE"); }
        const limit = data.storageQuota.limit ? Number(data.storageQuota.limit) : null;
        const usage = Number(data.storageQuota.usage ?? 0);
        return json({ ok: true, email, quotaBytes: limit, usedBytes: usage, availableBytes: limit === null ? null : Math.max(0, limit - usage), appMaxUploadBytes: MAX_BYTES });
      }

      if (body.action === "start_upload") {
        const orderId = String(body.orderId ?? "");
        const filename = String(body.filename ?? "").trim().slice(0, 240);
        const size = Number(body.sizeBytes);
        const mime = String(body.mimeType ?? "application/octet-stream");
        if (!orderId || !filename || !Number.isSafeInteger(size) || size <= 0 || size > MAX_BYTES || !/^[\w.+-]+\/[\w.+-]+$/.test(mime)) throw new Error("FILE_SIZE_INVALID");
        const { data: order, error: orderError } = await admin.from("wedding_orders").select("id,customer_id,payment_status,upload_locked").eq("id", orderId).eq("customer_id", customerId).maybeSingle();
        if (orderError || !order) throw new Error("ORDER_NOT_FOUND");
        if (order.upload_locked) throw new Error("UPLOAD_LOCKED");
        // Multiple videos are allowed in one wedding order; uploads are serialized by the app.
        const quotaRes = await driveRequest("https://www.googleapis.com/drive/v3/about?fields=storageQuota(limit,usage)", accessToken);
        const quota = await quotaRes.json();
        if (!quotaRes.ok || !quota.storageQuota) { googleApiDiagnostic("start_upload_quota", quotaRes.status, quota); throw new Error("DRIVE_QUOTA_UNAVAILABLE"); }
        if (quota.storageQuota.limit) {
          const available = Number(quota.storageQuota.limit) - Number(quota.storageQuota.usage ?? 0);
          if (available < size) throw new Error("INSUFFICIENT_DRIVE_SPACE");
        }
        const folder = await ensureFolder(admin, customerId, accessToken, existingFolder);
        const initRes = await driveRequest("https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,name,mimeType,size,parents,md5Checksum", accessToken, {
          method: "POST",
          headers: {
            "Content-Type": "application/json; charset=UTF-8",
            "X-Upload-Content-Type": mime,
            "X-Upload-Content-Length": String(size),
          },
          body: JSON.stringify({ name: filename, mimeType: mime, parents: [folder] }),
        });
        const sessionUri = initRes.headers.get("Location");
        if (!initRes.ok || !sessionUri || !sessionUri.startsWith("https://www.googleapis.com/")) throw new Error("UPLOAD_SESSION_CREATE_FAILED");
        const { data: saved, error: saveError } = await admin.rpc("gdrive_upload_session_save", {
          p_order_id: orderId, p_customer_id: customerId, p_session_uri: sessionUri,
          p_expected_size_bytes: size, p_original_filename: filename, p_mime_type: mime,
        });
        if (saveError || saved !== true) throw new Error("UPLOAD_SESSION_SAVE_FAILED");
        await admin.from("wedding_orders").update({ workflow_status: "uploading" }).eq("id", orderId).eq("customer_id", customerId);
        return json({ ok: true, uploadUrl: sessionUri, chunkSizeBytes: 8388608, expiresInDays: 7, expectedSizeBytes: size });
      }

      if (body.action === "finalize_upload") {
        const orderId = String(body.orderId ?? "");
        const fileId = String(body.fileId ?? "");
        if (!orderId || !fileId || !/^[\w-]{10,}$/.test(fileId)) throw new Error("DRIVE_FILE_NOT_VERIFIED");
        const { data: sessions, error: sessionError } = await admin.rpc("gdrive_upload_session_get", { p_order_id: orderId, p_customer_id: customerId });
        const session = Array.isArray(sessions) ? sessions[0] : null;
        if (sessionError || !session) throw new Error("UPLOAD_SESSION_NOT_FOUND");
        const metaRes = await driveRequest("https://www.googleapis.com/drive/v3/files/" + encodeURIComponent(fileId) + "?fields=id,name,mimeType,size,parents,md5Checksum,trashed,owners(emailAddress)", accessToken);
        const meta = await metaRes.json();
        if (!metaRes.ok || meta.trashed || String(meta.size) !== String(session.expected_size_bytes) ||
            meta.name !== session.original_filename || meta.mimeType !== session.mime_type ||
            !Array.isArray(meta.parents) || !meta.parents.includes(await ensureFolder(admin, customerId, accessToken, existingFolder)) ||
            !Array.isArray(meta.owners) || !meta.owners.some((o: any) => o.emailAddress?.toLowerCase() === email.toLowerCase())) {
          throw new Error("DRIVE_FILE_NOT_VERIFIED");
        }
        const { data: order, error: orderError } = await admin.from("wedding_orders").select("id,customer_id,payment_status,upload_locked").eq("id", orderId).eq("customer_id", customerId).maybeSingle();
        if (orderError || !order) throw new Error("ORDER_NOT_FOUND");
        if (order.upload_locked) throw new Error("UPLOAD_LOCKED");
        const { error: insertError } = await admin.from("wedding_videos").insert({
          order_id: orderId, customer_id: customerId, original_filename: session.original_filename,
          storage_bucket: "google-drive", storage_path: null, mime_type: session.mime_type,
          file_size_bytes: Number(session.expected_size_bytes), sha256_hex: null,
          upload_status: "uploaded", uploaded_at: new Date().toISOString(),
          google_drive_file_id: fileId, google_drive_account_email: email,
        });
        if (insertError) throw new Error("VIDEO_RECORD_SAVE_FAILED");
        await admin.from("wedding_orders").update({ workflow_status: "video_ready_to_share" }).eq("id", orderId).eq("customer_id", customerId);
        await admin.rpc("gdrive_upload_session_complete", { p_order_id: orderId, p_customer_id: customerId, p_file_id: fileId });
        await admin.from("audit_events").insert({ actor_user_id: customerId, order_id: orderId, event_type: "google_drive_video_uploaded", event_data: { file_id: fileId, size_bytes: Number(session.expected_size_bytes) } });
        return json({ ok: true, status: "uploaded", fileId, filename: meta.name, sizeBytes: Number(meta.size), md5Checksum: meta.md5Checksum ?? null });
      }

      if (body.action === "delete_video") {
        const videoId = String(body.videoId ?? "");
        const { data: video, error: videoError } = await admin.from("wedding_videos").select("id,order_id,google_drive_file_id,upload_status").eq("id", videoId).eq("customer_id", customerId).is("deleted_at", null).maybeSingle();
        if (videoError || !video) throw new Error("VIDEO_NOT_FOUND");
        if (!video.google_drive_file_id) throw new Error("VIDEO_NOT_FOUND");
        const delRes = await driveRequest("https://www.googleapis.com/drive/v3/files/" + encodeURIComponent(video.google_drive_file_id), accessToken, { method: "DELETE" });
        if (!delRes.ok && delRes.status !== 404) throw new Error("GOOGLE_DRIVE_DELETE_FAILED");
        const now = new Date().toISOString();
        const { error: updateError } = await admin.from("wedding_videos").update({ upload_status: "deleted", deleted_at: now, google_drive_file_id: null, storage_path: null }).eq("id", videoId).eq("customer_id", customerId);
        if (updateError) throw new Error("GOOGLE_DRIVE_DELETE_FAILED");
        await admin.from("audit_events").insert({ actor_user_id: customerId, order_id: video.order_id, event_type: "customer_deleted_google_drive_video", event_data: { video_id: videoId } });
        return json({ ok: true, deleted: true, note: "Only the Google Drive copy was deleted; the phone original was not touched." });
      }

      throw new Error("ACTION_NOT_SUPPORTED");
    } catch (e) {
      const error = parseError(e);
      const status = error === "GOOGLE_OAUTH_NOT_CONFIGURED" ? 503 :
        error === "ORDER_NOT_FOUND" || error === "VIDEO_NOT_FOUND" || error === "UPLOAD_SESSION_NOT_FOUND" ? 404 :
        error === "INTERNAL_ERROR" ? 500 : 400;
      return json({ ok: false, error }, status);
    }
  });
  return handler(req);
});
