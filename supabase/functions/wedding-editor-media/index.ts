import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,apikey,content-type,x-client-info","Access-Control-Allow-Methods":"GET,POST,OPTIONS","Vary":"Origin"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
const b64=(s:string)=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const unhex=(s:string)=>Uint8Array.from((s.match(/.{1,2}/g)??[]).map(x=>parseInt(x,16)));
const MAX_BYTES=40000000000;
function adminClient(){const url=Deno.env.get("SUPABASE_URL"),raw=Deno.env.get("SUPABASE_SECRET_KEYS");let key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??Deno.env.get("SERVICE_ROLE_KEY");if(!key&&raw){try{key=JSON.parse(raw).default}catch{}}if(!url||!key)throw Error("BACKEND_CONFIG");return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}})}
async function driveContext(admin:any,owner:string){const clientId=Deno.env.get("GOOGLE_CLIENT_ID"),clientSecret=Deno.env.get("GOOGLE_CLIENT_SECRET"),encryptionKey=Deno.env.get("GOOGLE_TOKEN_ENCRYPTION_KEY");if(!clientId||!clientSecret||!encryptionKey)throw Error("GOOGLE_OAUTH_NOT_CONFIGURED");const {data,error}=await admin.rpc("gdrive_connection_get",{p_customer_id:owner});const row=Array.isArray(data)?data[0]:null;if(error||!row?.encrypted_refresh_token_hex)throw Error("GOOGLE_DRIVE_NOT_CONNECTED");const keyBytes=b64(encryptionKey);if(keyBytes.length!==32)throw Error("GOOGLE_ENCRYPTION_KEY_INVALID");const packed=unhex(row.encrypted_refresh_token_hex);const key=await crypto.subtle.importKey("raw",keyBytes,{name:"AES-GCM"},false,["decrypt"]);const plain=await crypto.subtle.decrypt({name:"AES-GCM",iv:packed.slice(0,12)},key,packed.slice(12));const refresh=new TextDecoder().decode(plain);const response=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:new URLSearchParams({client_id:clientId,client_secret:clientSecret,refresh_token:refresh,grant_type:"refresh_token"})});const token=await response.json();if(!response.ok||!token.access_token)throw Error("GOOGLE_TOKEN_REFRESH_FAILED");return {token:token.access_token,email:String(row.google_account_email??""),folderId:row.google_drive_folder_id??null}}
async function driveFetch(url:string,token:string,init:RequestInit={}){const headers=new Headers(init.headers);headers.set("Authorization","Bearer "+token);return fetch(url,{...init,headers})}
async function membership(admin:any,editorId:string,userId:string,canEdit=true){const {data:editor,error}=await admin.from("wedding_editor_projects").select("id,project_id,owner_customer_id").eq("id",editorId).maybeSingle();if(error||!editor)throw Error("EDITOR_PROJECT_NOT_FOUND");if(editor.owner_customer_id===userId)return editor;const {data:project}=await admin.from("wedding_projects").select("owner_customer_id").eq("id",editor.project_id).maybeSingle();if(project?.owner_customer_id===userId)return editor;const {data:invite}=await admin.from("wedding_project_invitations").select("id").eq("project_id",editor.project_id).eq("invitee_user_id",userId).eq("status","accepted").eq("can_view",true).gt("expires_at",new Date().toISOString()).maybeSingle();if(!invite||(canEdit&&invite.can_edit!==true))throw Error("PROJECT_ACCESS_DENIED");return editor}
async function requestUser(req:Request,admin:any){const auth=req.headers.get("Authorization")??"",token=auth.replace(/^Bearer\\s+/i,"");if(!token||token===auth)throw Error("AUTH_REQUIRED");const {data,error}=await admin.auth.getUser(token);if(error||!data.user)throw Error("INVALID_SESSION");return data.user}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 const admin=adminClient();
 try{
  const user=await requestUser(req,admin);
  if(req.method==="GET"){
   const url=new URL(req.url),editorId=url.searchParams.get("editorProjectId")??"",fileId=url.searchParams.get("fileId")??"";
   const editor=await membership(admin,editorId,user.id,false);
   const {data:asset,error}=await admin.from("wedding_editor_media_assets").select("drive_file_id,original_filename,mime_type,media_kind").eq("editor_project_id",editorId).eq("drive_file_id",fileId).is("deleted_at",null).maybeSingle();
   if(error||!asset)return new Response("Media not found",{status:404,headers:cors});
   const drive=await driveContext(admin,editor.owner_customer_id);
   const response=await driveFetch("https://www.googleapis.com/drive/v3/files/"+encodeURIComponent(fileId)+"?alt=media",drive.token);
   if(!response.ok)return new Response("Google Drive media unavailable",{status:502,headers:cors});
   const headers=new Headers(cors);headers.set("Content-Type",asset.mime_type);headers.set("Content-Disposition","attachment; filename*=UTF-8''"+encodeURIComponent(asset.original_filename));headers.set("Cache-Control","private,no-store");const len=response.headers.get("Content-Length");if(len)headers.set("Content-Length",len);
   return new Response(response.body,{status:200,headers});
  }
  if(req.method!=="POST")return json({error:"METHOD_NOT_ALLOWED"},405);
  const body=await req.json(),action=String(body.action??""),editorId=String(body.editorProjectId??"");
  const editor=await membership(admin,editorId,user.id,true);
  const drive=await driveContext(admin,editor.owner_customer_id);
  if(action==="start"){
   const name=String(body.filename??"").trim().slice(0,240),size=Number(body.sizeBytes),mime=String(body.mimeType??"application/octet-stream"),kind=String(body.mediaKind??"");
   if(!name||!Number.isSafeInteger(size)||size<1||size>MAX_BYTES||!["video","audio","image"].includes(kind)||!new RegExp("^(video|audio|image)/[\\w.+-]+$","i").test(mime))return json({error:"INVALID_MEDIA"},400);
   const quotaRes=await driveFetch("https://www.googleapis.com/drive/v3/about?fields=storageQuota(limit,usage)",drive.token),quota=await quotaRes.json();
   if(!quotaRes.ok||!quota.storageQuota)return json({error:"DRIVE_QUOTA_UNAVAILABLE"},503);
   if(quota.storageQuota.limit&&Number(quota.storageQuota.limit)-Number(quota.storageQuota.usage??0)<size)return json({error:"INSUFFICIENT_DRIVE_SPACE"},409);
   const metadata:any={name,mimeType:mime};if(drive.folderId)metadata.parents=[drive.folderId];
   const init=await driveFetch("https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,name,mimeType,size,parents,owners(emailAddress)",drive.token,{method:"POST",headers:{"Content-Type":"application/json; charset=UTF-8","X-Upload-Content-Type":mime,"X-Upload-Content-Length":String(size)},body:JSON.stringify(metadata)});
   const uploadUrl=init.headers.get("Location");if(!init.ok||!uploadUrl||!uploadUrl.startsWith("https://www.googleapis.com/"))return json({error:"DRIVE_UPLOAD_SESSION_FAILED"},502);
   const sessionId=crypto.randomUUID();
   const {data:saved,error:saveError}=await admin.rpc("wedding_editor_media_session_save",{p_session_id:sessionId,p_editor_project_id:editorId,p_project_id:editor.project_id,p_owner_customer_id:editor.owner_customer_id,p_google_session_uri:uploadUrl,p_original_filename:name,p_mime_type:mime,p_expected_size_bytes:size,p_media_kind:kind});
   if(saveError||saved!==true)return json({error:"UPLOAD_SESSION_SAVE_FAILED"},500);
   return json({ok:true,sessionId,uploadUrl,chunkSizeBytes:8388608,expectedSizeBytes:size});
  }
  if(action==="finalize"){
   const sessionId=String(body.sessionId??""),fileId=String(body.fileId??"");
   const {data:sessions,error}=await admin.rpc("wedding_editor_media_session_get",{p_session_id:sessionId,p_editor_project_id:editorId});
   const session=Array.isArray(sessions)?sessions[0]:null;
   if(error||!session||! /^[\\w-]{10,}$/.test(fileId))return json({error:"UPLOAD_SESSION_NOT_FOUND"},404);
   const metaRes=await driveFetch("https://www.googleapis.com/drive/v3/files/"+encodeURIComponent(fileId)+"?fields=id,name,mimeType,size,parents,owners(emailAddress),trashed",drive.token),meta=await metaRes.json();
   if(!metaRes.ok||meta.trashed||String(meta.size)!==String(session.expected_size_bytes)||meta.name!==session.original_filename||meta.mimeType!==session.mime_type||!Array.isArray(meta.owners)||!meta.owners.some((o:any)=>String(o.emailAddress).toLowerCase()===drive.email.toLowerCase()))return json({error:"DRIVE_FILE_NOT_VERIFIED"},400);
   const {error:insertError}=await admin.from("wedding_editor_media_assets").insert({editor_project_id:editorId,project_id:editor.project_id,owner_customer_id:editor.owner_customer_id,drive_file_id:fileId,original_filename:session.original_filename,mime_type:session.mime_type,file_size_bytes:Number(session.expected_size_bytes),media_kind:session.media_kind});
   if(insertError&&insertError.code!=="23505")return json({error:"MEDIA_ASSET_SAVE_FAILED"},500);
   await admin.rpc("wedding_editor_media_session_complete",{p_session_id:sessionId,p_editor_project_id:editorId});
   await admin.rpc("wedding_editor_media_ids_append",{p_editor_project_id:editorId,p_file_id:fileId});
   return json({ok:true,fileId,name:meta.name,mimeType:meta.mimeType,sizeBytes:Number(meta.size),mediaKind:session.media_kind});
  }
  if(action==="list"){
   const {data,error}=await admin.from("wedding_editor_media_assets").select("drive_file_id,original_filename,mime_type,file_size_bytes,media_kind,created_at").eq("editor_project_id",editorId).is("deleted_at",null).order("created_at");
   if(error)return json({error:"MEDIA_LIST_FAILED"},500);
   return json({ok:true,assets:data??[]});
  }
  return json({error:"ACTION_NOT_SUPPORTED"},400);
 }catch(e){const message=e instanceof Error?e.message:"INTERNAL_ERROR";const status=message==="AUTH_REQUIRED"||message==="INVALID_SESSION"?401:message==="EDITOR_PROJECT_NOT_FOUND"||message==="UPLOAD_SESSION_NOT_FOUND"?404:message==="PROJECT_ACCESS_DENIED"?403:message==="GOOGLE_DRIVE_NOT_CONNECTED"||message==="GOOGLE_OAUTH_NOT_CONFIGURED"?503:400;return json({error:message},status)}
});