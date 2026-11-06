import { withSupabase } from "npm:@supabase/server@^1";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
const hex = (b: Uint8Array) => Array.from(b).map(x => x.toString(16).padStart(2, "0")).join("");
const hash = async (s: string) => hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))));
const hexBytes = (s: string) => Uint8Array.from((s.match(/.{1,2}/g) ?? []).map(x => parseInt(x, 16)));
const b64bytes = (s: string) => Uint8Array.from(atob(s), c => c.charCodeAt(0));

function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  let key = Deno.env.get("SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!key && raw) { try { key = JSON.parse(raw)["default"]; } catch { /* fallback */ } }
  if (!url || !key) throw new Error("SERVER_CONFIGURATION_MISSING");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

async function accessToken(admin: any, customerId: string) {
  const clientId = Deno.env.get("GOOGLE_CLIENT_ID");
  const clientSecret = Deno.env.get("GOOGLE_CLIENT_SECRET");
  const encryptionKey = Deno.env.get("GOOGLE_TOKEN_ENCRYPTION_KEY");
  if (!clientId || !clientSecret || !encryptionKey) throw new Error("GOOGLE_OAUTH_NOT_CONFIGURED");
  const { data, error } = await admin.rpc("gdrive_connection_get", { p_customer_id: customerId });
  const row = Array.isArray(data) ? data[0] : null;
  if (error || !row?.encrypted_refresh_token_hex) throw new Error("GOOGLE_DRIVE_NOT_CONNECTED");
  const raw = b64bytes(encryptionKey);
  if (raw.length !== 32) throw new Error("GOOGLE_TOKEN_ENCRYPTION_KEY_MUST_BE_32_BYTE_BASE64");
  const cipher = hexBytes(row.encrypted_refresh_token_hex);
  const key = await crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, ["decrypt"]);
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: cipher.slice(0, 12) }, key, cipher.slice(12));
  const refreshToken = new TextDecoder().decode(plain);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret, refresh_token: refreshToken, grant_type: "refresh_token" }),
  });
  const tokens = await response.json();
  if (!response.ok || typeof tokens.access_token !== "string") throw new Error("GOOGLE_ACCESS_TOKEN_REFRESH_FAILED");
  return { token: tokens.access_token as string, email: row.google_account_email as string };
}

async function driveFetch(url: string, token: string, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("Authorization", "Bearer " + token);
  return fetch(url, { ...init, headers });
}

function errName(e: unknown) {
  const m = e instanceof Error ? e.message : "INTERNAL_ERROR";
  const known = ["GOOGLE_OAUTH_NOT_CONFIGURED","GOOGLE_DRIVE_NOT_CONNECTED","GOOGLE_TOKEN_ENCRYPTION_KEY_MUST_BE_32_BYTE_BASE64","GOOGLE_ACCESS_TOKEN_REFRESH_FAILED","ORDER_NOT_FOUND","VIDEO_NOT_READY","GOOGLE_PERMISSION_CREATE_FAILED","SHARE_CREATE_FAILED","SHARE_INVALID","VIDEO_UNAVAILABLE","SERVER_CONFIGURATION_MISSING"];
  return known.includes(m) ? m : "INTERNAL_ERROR";
}

async function redirectForToken(token: string) {
  if (!/^[a-f0-9]{64}$/.test(token)) return new Response("Invalid or expired share link.", { status: 404 });
  const admin = adminClient();
  const { data: share } = await admin.from("share_links").select("id,order_id,is_active,expires_at,revoked_at").eq("token_hash", await hash(token)).maybeSingle();
  if (!share || !share.is_active || share.revoked_at || (share.expires_at && new Date(share.expires_at).getTime() <= Date.now())) {
    return new Response("This share link is invalid, expired, or revoked.", { status: 404 });
  }
  const { data: order } = await admin.from("wedding_orders").select("id,customer_id,payment_status").eq("id", share.order_id).maybeSingle();
  if (!order || order.payment_status !== "paid") return new Response("This video is not available.", { status: 404 });
  const { data: videos } = await admin.from("wedding_videos")
    .select("id,original_filename,file_size_bytes,upload_status")
    .eq("order_id", order.id).eq("upload_status", "uploaded").is("deleted_at", null)
    .order("created_at", { ascending: true }).limit(10);
  if (!videos || videos.length === 0) return new Response("No videos are available.", { status: 404 });
  await admin.from("audit_events").insert({ order_id: order.id, event_type: "receiver_download_link_opened", event_data: { video_count: videos.length } });
  return Response.redirect("https://wedding-video-download.weddingvideoshare-ym.workers.dev/?token=" + encodeURIComponent(token), 302);
}


async function workerInternal(req: Request, body: Record<string, unknown>) {
 const supplied=req.headers.get("x-download-worker-secret")??"";
 const admin=adminClient();
 const {data:authorized}=await admin.rpc("verify_download_worker_secret",{p_secret_hash:await hash(supplied)});
 if(!supplied||authorized!==true)return json({error:"WORKER_AUTH_FAILED"},401);
 if(body.action==="worker_list"){
  const t=String(body.token??"");
  if(!/^[a-f0-9]{64}$/.test(t))return json({error:"SHARE_INVALID"},404);
  const {data:s}=await admin.from("share_links").select("id,order_id,is_active,expires_at,revoked_at").eq("token_hash",await hash(t)).maybeSingle();
  if(!s||!s.is_active||s.revoked_at||(s.expires_at&&new Date(s.expires_at).getTime()<=Date.now()))return json({error:"SHARE_INVALID"},404);
  const pin=String(body.pin??"");
  if(!/^\\d{6}$/.test(pin))return json({error:"PIN_REQUIRED"},400);
  const candidateHash=await hash(t+":"+pin);
  const {data:pinOk,error:pinError}=await admin.rpc("verify_share_download_pin",{p_token_hash:await hash(t),p_candidate_hash:candidateHash});
  if(pinError||pinOk!==true)return json({error:"PIN_INVALID_OR_LOCKED"},403);
  const {data:o}=await admin.from("wedding_orders").select("id,payment_status").eq("id",s.order_id).maybeSingle();
  if(!o||o.payment_status!=="paid")return json({error:"VIDEO_UNAVAILABLE"},404);
  const {data:videos,error}=await admin.from("wedding_videos")
    .select("id,original_filename,mime_type,file_size_bytes,upload_status,auto_delete_consent_at")
    .eq("order_id",o.id).eq("upload_status","uploaded").is("deleted_at",null)
    .order("created_at",{ascending:true}).limit(10);
  if(error||!videos||videos.length===0)return json({error:"VIDEO_UNAVAILABLE"},404);
  return json({ok:true,videos:videos.map((v:any)=>({id:v.id,filename:v.original_filename,mimeType:v.mime_type||"application/octet-stream",expectedBytes:Number(v.file_size_bytes),autoDeleteConsent:v.auto_delete_consent_at!==null}))});
 }
 if(body.action==="worker_prepare"){
  const t=String(body.token??"");
  if(!/^[a-f0-9]{64}$/.test(t))return json({error:"SHARE_INVALID"},404);
  const {data:s}=await admin.from("share_links").select("id,order_id,is_active,expires_at,revoked_at").eq("token_hash",await hash(t)).maybeSingle();
  if(!s||!s.is_active||s.revoked_at||(s.expires_at&&new Date(s.expires_at).getTime()<=Date.now()))return json({error:"SHARE_INVALID"},404);
  const pin=String(body.pin??"");
  if(!/^\d{6}$/.test(pin))return json({error:"PIN_REQUIRED"},400);
  const candidateHash=await hash(t+":"+pin);
  const {data:pinOk,error:pinError}=await admin.rpc("verify_share_download_pin",{p_token_hash:await hash(t),p_candidate_hash:candidateHash});
  if(pinError||pinOk!==true)return json({error:"PIN_INVALID_OR_LOCKED"},403);
  const {data:o}=await admin.from("wedding_orders").select("id,customer_id,payment_status").eq("id",s.order_id).maybeSingle();
  if(!o||o.payment_status!=="paid")return json({error:"VIDEO_UNAVAILABLE"},404);
  const videoId=String(body.videoId??"");
  if(!videoId)return json({error:"VIDEO_ID_REQUIRED"},400);
  const {data:v}=await admin.from("wedding_videos").select("id,google_drive_file_id,original_filename,mime_type,file_size_bytes,upload_status,auto_delete_consent_at").eq("order_id",o.id).eq("id",videoId).maybeSingle();
  if(!v||v.upload_status!=="uploaded"||!v.google_drive_file_id)return json({error:"VIDEO_UNAVAILABLE"},404);
  const {token}=await accessToken(admin,o.customer_id);
  const check=await driveFetch("https://www.googleapis.com/drive/v3/files/"+encodeURIComponent(v.google_drive_file_id)+"?fields=id,size,trashed",token);
  const meta=await check.json();
  if(!check.ok||meta.trashed||String(meta.size)!==String(v.file_size_bytes))return json({error:"DRIVE_FILE_NOT_VERIFIED"},503);
  const {data:d,error}=await admin.from("receiver_downloads").insert({order_id:o.id,video_id:v.id,share_link_id:s.id,status:"downloading",bytes_expected:v.file_size_bytes,bytes_transferred:0,checksum_verified:false,transfer_verified:false}).select("id").single();
  if(error||!d)return json({error:"DOWNLOAD_SESSION_CREATE_FAILED"},500);
  return json({ok:true,downloadId:d.id,shareLinkId:s.id,googleAccessToken:token,fileId:v.google_drive_file_id,filename:v.original_filename,mimeType:v.mime_type||"application/octet-stream",expectedBytes:Number(v.file_size_bytes)});
 }
 if(body.action==="worker_complete"){
  const id=String(body.downloadId??""),shareId=String(body.shareLinkId??""),bytes=Number(body.bytesTransferred??-1),done=body.completed===true;
  if(!/^[0-9a-f-]{36}$/i.test(id)||!/^[0-9a-f-]{36}$/i.test(shareId))return json({error:"DOWNLOAD_SESSION_NOT_FOUND"},404);
  const {data:r}=await admin.from("receiver_downloads").select("id,bytes_expected,video_id,order_id,status").eq("id",id).eq("share_link_id",shareId).maybeSingle();
  if(!r)return json({error:"DOWNLOAD_SESSION_NOT_FOUND"},404);
  const valid=done&&Number.isSafeInteger(bytes)&&bytes===Number(r.bytes_expected),now=new Date().toISOString();
  if (r.status !== "completed") {
   const {error}=await admin.from("receiver_downloads").update({status:valid?"completed":"interrupted",bytes_transferred:Math.max(0,Math.min(Number(r.bytes_expected),Number.isFinite(bytes)?bytes:0)),transfer_verified:valid,checksum_verified:false,completed_at:valid?now:null,verified_at:valid?now:null}).eq("id",id).eq("share_link_id",shareId);
   if(error)return json({error:"DOWNLOAD_SESSION_UPDATE_FAILED"},500);
  }
  if (!valid && r.status !== "completed") return json({ok:true,completed:false,deleted:false});
  const {data:video}=await admin.from("wedding_videos").select("id,customer_id,google_drive_file_id,upload_status,auto_delete_consent_at").eq("id",r.video_id).maybeSingle();
  if (!video || !video.auto_delete_consent_at) return json({ok:true,completed:true,deleted:false,deleteReason:"CONSENT_NOT_FOUND"});
  if (video.upload_status === "deleted" || !video.google_drive_file_id) return json({ok:true,completed:true,deleted:true});
  try {
   const {token}=await accessToken(admin,video.customer_id);
   const del=await driveFetch("https://www.googleapis.com/drive/v3/files/"+encodeURIComponent(video.google_drive_file_id),token,{method:"DELETE"});
   if (!del.ok && del.status !== 404) return json({ok:true,completed:true,deleted:false,deleteReason:"GOOGLE_DRIVE_DELETE_FAILED"});
   const {error:saveError}=await admin.from("wedding_videos").update({upload_status:"deleted",deleted_at:now,google_drive_file_id:null,storage_path:null}).eq("id",video.id).eq("customer_id",video.customer_id);
   if(saveError)return json({ok:true,completed:true,deleted:false,deleteReason:"DELETE_RECORD_UPDATE_FAILED"});
   await admin.from("audit_events").insert({actor_user_id:video.customer_id,order_id:r.order_id,event_type:"google_drive_video_auto_deleted_after_verified_download",event_data:{video_id:video.id,download_id:id,bytes_transferred:bytes}});
   return json({ok:true,completed:true,deleted:true});
  } catch (_) {
   return json({ok:true,completed:true,deleted:false,deleteReason:"GOOGLE_DRIVE_DELETE_FAILED"});
  }
 }
 return json({error:"ACTION_NOT_SUPPORTED"},400);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method === "POST" && req.headers.has("x-download-worker-secret")) {
    let b: Record<string, unknown>;
    try { b = await req.json(); } catch { return json({ error: "INVALID_JSON" }, 400); }
    return await workerInternal(req, b);
  }
  const url = new URL(req.url);
  if (req.method === "GET" && url.searchParams.has("token")) {
    try { return await redirectForToken(url.searchParams.get("token") ?? ""); }
    catch { return new Response("The video link could not be opened. Please contact the sender.", { status: 503 }); }
  }
  if (req.method !== "POST") return json({ error: "POST_REQUIRED" }, 405);
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "INVALID_JSON" }, 400); }
  if (body.action !== "create_share") return json({ error: "ACTION_NOT_SUPPORTED" }, 400);
  const handler = withSupabase({ auth: "user" }, async (_request, ctx) => {
    try {
      const orderId = String(body.orderId ?? "");
      if (!orderId) return json({ error: "ORDER_NOT_FOUND" }, 404);
      const admin = ctx.supabaseAdmin;
      const customerId = ctx.userClaims.sub;
      const { data: order } = await admin.from("wedding_orders").select("id,customer_id,payment_status,upload_locked").eq("id", orderId).eq("customer_id", customerId).maybeSingle();
      if (!order || order.payment_status !== "paid") throw new Error("ORDER_NOT_FOUND");
      const { data: videos, error: videosError } = await admin.from("wedding_videos")
        .select("id,google_drive_file_id,upload_status")
        .eq("order_id", orderId).eq("customer_id", customerId)
        .eq("upload_status", "uploaded").is("deleted_at", null);
      if (videosError || !videos || videos.length === 0 || videos.some((v: any) => !v.google_drive_file_id)) throw new Error("VIDEO_NOT_READY");
      const { token: googleToken } = await accessToken(admin, customerId);
      const rawToken = new Uint8Array(32);
      crypto.getRandomValues(rawToken);
      const shareToken = hex(rawToken);
      const pinRandom = new Uint32Array(1);
      crypto.getRandomValues(pinRandom);
      const downloadPin = String(pinRandom[0] % 1000000).padStart(6, "0");
      const downloadPinHash = await hash(shareToken + ":" + downloadPin);
      const { data: existingShare } = await admin.from("share_links").select("id").eq("order_id", orderId).maybeSingle();
      let shareError;
      if (existingShare?.id) {
        const updated = await admin.from("share_links").update({ token_hash: await hash(shareToken), download_pin_hash: downloadPinHash, download_pin_attempts: 0, download_pin_locked_until: null, is_active: true, revoked_at: null, expires_at: null }).eq("id", existingShare.id);
        shareError = updated.error;
      } else {
        const created = await admin.from("share_links").insert({ order_id: orderId, token_hash: await hash(shareToken), download_pin_hash: downloadPinHash, download_pin_attempts: 0, download_pin_locked_until: null, is_active: true });
        shareError = created.error;
      }
      if (shareError) throw new Error("SHARE_CREATE_FAILED");
      await admin.from("audit_events").insert({ actor_user_id: customerId, order_id: orderId, event_type: "google_drive_share_link_created", event_data: { video_ids: videos.map((v: any) => v.id), video_count: videos.length } });
      const base = Deno.env.get("SUPABASE_URL");
      return json({ ok: true, shareUrl: base + "/functions/v1/wedding-share?token=" + shareToken, downloadPin, note: "Send the private link and six-digit PIN separately. Five wrong attempts lock the PIN for 15 minutes." });
    } catch (e) {
      const error = errName(e);
      const status = error === "ORDER_NOT_FOUND" ? 404 : error === "GOOGLE_OAUTH_NOT_CONFIGURED" ? 503 : error === "INTERNAL_ERROR" ? 500 : 400;
      return json({ ok: false, error }, status);
    }
  });
  return handler(req);
});