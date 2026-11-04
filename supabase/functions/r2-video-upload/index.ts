import { withSupabase } from "npm:@supabase/server@^1";
import {
  S3Client, CreateMultipartUploadCommand, UploadPartCommand,
  CompleteMultipartUploadCommand, AbortMultipartUploadCommand, HeadObjectCommand,
} from "npm:@aws-sdk/client-s3@3.850.0";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner@3.850.0";

const MAX_BYTES = 50 * 1024 ** 3;
const PART_BYTES = 64 * 1024 ** 2;
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function r2Config() {
  const account = Deno.env.get("R2_ACCOUNT_ID"), access = Deno.env.get("R2_ACCESS_KEY_ID"), secret = Deno.env.get("R2_SECRET_ACCESS_KEY"), bucket = Deno.env.get("R2_BUCKET_NAME");
  if (!account || !access || !secret || !bucket) return null;
  return { bucket, client: new S3Client({ region: "auto", endpoint: `https://${account}.r2.cloudflarestorage.com`, credentials: { accessKeyId: access, secretAccessKey: secret } }) };
}

Deno.serve(withSupabase({ auth: "user" }, async (req, ctx) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);
  const r2 = r2Config();
  if (!r2) return json({ error: "R2_NOT_CONFIGURED", message: "Set R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY and R2_BUCKET_NAME in Supabase Edge Function secrets." }, 503);

  let b: Record<string, unknown>;
  try { b = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  if (typeof b.orderId !== "string") return json({ error: "orderId required" }, 400);

  const { data: order, error } = await ctx.supabase.from("wedding_orders")
    .select("id, customer_id, payment_status, upload_locked, workflow_status")
    .eq("id", b.orderId).maybeSingle();
  if (error || !order) return json({ error: "Order not found" }, 404);
  if (order.payment_status !== "paid") return json({ error: "Payment is not verified" }, 403);
  if (order.upload_locked || order.workflow_status === "upload_locked") return json({ error: "Upload locked" }, 409);

  const admin = ctx.supabaseAdmin;
  if (b.action === "create") {
    const size = Number(b.fileSizeBytes), filename = typeof b.filename === "string" ? b.filename.trim() : "";
    const contentType = typeof b.contentType === "string" ? b.contentType : "video/mp4";
    if (!Number.isSafeInteger(size) || size < 1 || size > MAX_BYTES) return json({ error: "Video must be 1 byte to 50 GB" }, 400);
    if (!filename || filename.length > 240) return json({ error: "Valid filename required" }, 400);
    const { data: existing, error: checkError } = await admin.from("wedding_videos").select("id").eq("order_id", b.orderId).maybeSingle();
    if (checkError) return json({ error: "Could not check existing video" }, 500);
    if (existing) return json({ error: "One video is already registered for this wedding" }, 409);
    const key = `orders/${order.id}/${crypto.randomUUID()}/original`;
    const started = await r2.client.send(new CreateMultipartUploadCommand({ Bucket: r2.bucket, Key: key, ContentType: contentType, Metadata: { order_id: order.id, customer_id: order.customer_id } }));
    if (!started.UploadId) return json({ error: "R2 did not return upload ID" }, 502);
    return json({ uploadId: started.UploadId, objectKey: key, partSizeBytes: PART_BYTES, totalParts: Math.ceil(size / PART_BYTES), maxFileSizeBytes: MAX_BYTES });
  }

  if (typeof b.uploadId !== "string" || typeof b.objectKey !== "string" || !b.objectKey.startsWith(`orders/${order.id}/`)) return json({ error: "Invalid upload session" }, 400);

  if (b.action === "sign_part") {
    const part = Number(b.partNumber), total = Number(b.totalParts);
    if (!Number.isInteger(part) || part < 1 || part > 10000 || !Number.isInteger(total) || total < 1 || total > 10000 || part > total) return json({ error: "Invalid part number" }, 400);
    const url = await getSignedUrl(r2.client, new UploadPartCommand({ Bucket: r2.bucket, Key: b.objectKey, UploadId: b.uploadId, PartNumber: part }), { expiresIn: 900 });
    return json({ url, expiresInSeconds: 900 });
  }

  if (b.action === "complete") {
    const size = Number(b.fileSizeBytes), filename = typeof b.filename === "string" ? b.filename.trim() : "";
    if (!Array.isArray(b.parts) || b.parts.length < 1 || b.parts.length > 10000 || !Number.isSafeInteger(size) || size < 1 || size > MAX_BYTES || !filename || filename.length > 240) return json({ error: "Invalid completion details" }, 400);
    const parts = b.parts.map((p: any) => ({ PartNumber: Number(p.partNumber), ETag: String(p.etag) })).sort((x: any, y: any) => x.PartNumber - y.PartNumber);
    if (parts.some((p: any, i: number) => !Number.isInteger(p.PartNumber) || p.PartNumber !== i + 1 || !p.ETag)) return json({ error: "Parts must be consecutive and include ETags" }, 400);
    await r2.client.send(new CompleteMultipartUploadCommand({ Bucket: r2.bucket, Key: b.objectKey, UploadId: b.uploadId, MultipartUpload: { Parts: parts } }));
    const head = await r2.client.send(new HeadObjectCommand({ Bucket: r2.bucket, Key: b.objectKey }));
    if (Number(head.ContentLength) !== size) return json({ error: "Stored size mismatch; support reconciliation required" }, 409);
    const { data: video, error: insertError } = await admin.from("wedding_videos").insert({
      order_id: order.id, customer_id: order.customer_id, original_filename: filename,
      storage_bucket: r2.bucket, storage_path: b.objectKey,
      mime_type: typeof b.contentType === "string" ? b.contentType : "video/mp4",
      file_size_bytes: size, upload_status: "uploaded", uploaded_at: new Date().toISOString(),
    }).select("id, order_id, file_size_bytes, upload_status").single();
    if (insertError) return json({ error: "Video is stored but database registration failed; preserve object for reconciliation" }, 500);
    await admin.from("wedding_orders").update({ workflow_status: "video_ready_to_share" }).eq("id", order.id);
    await admin.from("audit_events").insert({ order_id: order.id, actor_user_id: order.customer_id, event_type: "video_upload_completed", event_data: { video_id: video.id, file_size_bytes: size } });
    return json({ ok: true, video });
  }

  if (b.action === "abort") {
    await r2.client.send(new AbortMultipartUploadCommand({ Bucket: r2.bucket, Key: b.objectKey, UploadId: b.uploadId }));
    return json({ ok: true, aborted: true });
  }
  return json({ error: "Unknown action" }, 400);
}));