import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,apikey,content-type,x-client-info","Access-Control-Allow-Methods":"POST,OPTIONS","Cache-Control":"no-store"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const ADMIN_EMAIL="ym6250067@gmail.com";
function admin(){const u=Deno.env.get("SUPABASE_URL"),raw=Deno.env.get("SUPABASE_SECRET_KEYS");let k=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??Deno.env.get("SERVICE_ROLE_KEY");if(!k&&raw){try{k=JSON.parse(raw).default}catch{}}if(!u||!k)throw Error("BACKEND_CONFIG");return createClient(u,k,{auth:{persistSession:false,autoRefreshToken:false}})}

const b64=(s:string)=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const unhex=(s:string)=>Uint8Array.from((s.match(/.{1,2}/g)??[]).map(x=>parseInt(x,16)));
async function driveQuota(a:any,ownerId:string){
 try{
  const clientId=Deno.env.get("GOOGLE_CLIENT_ID"),clientSecret=Deno.env.get("GOOGLE_CLIENT_SECRET"),enc=Deno.env.get("GOOGLE_TOKEN_ENCRYPTION_KEY");
  if(!clientId||!clientSecret||!enc)return {ownerId,connected:false,reason:"Google Drive integration is not configured"};
  const {data,error}=await a.rpc("gdrive_connection_get",{p_customer_id:ownerId});
  const row=Array.isArray(data)?data[0]:null;
  if(error||!row?.encrypted_refresh_token_hex)return {ownerId,connected:false,reason:"Not connected"};
  const keyBytes=b64(enc);if(keyBytes.length!==32)return {ownerId,connected:false,reason:"Encryption configuration unavailable"};
  const bytes=unhex(row.encrypted_refresh_token_hex);
  const key=await crypto.subtle.importKey("raw",keyBytes,{name:"AES-GCM"},false,["decrypt"]);
  const plain=await crypto.subtle.decrypt({name:"AES-GCM",iv:bytes.slice(0,12)},key,bytes.slice(12));
  const refresh=new TextDecoder().decode(plain);
  const tokenRes=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:new URLSearchParams({client_id:clientId,client_secret:clientSecret,refresh_token:refresh,grant_type:"refresh_token"})});
  const token=await tokenRes.json();if(!tokenRes.ok||!token.access_token)return {ownerId,connected:false,reason:"Token refresh failed"};
  const quotaRes=await fetch("https://www.googleapis.com/drive/v3/about?fields=storageQuota(limit,usage)",{headers:{Authorization:"Bearer "+token.access_token}});
  const quota=await quotaRes.json();if(!quotaRes.ok||!quota.storageQuota)return {ownerId,connected:true,quotaAvailable:false,reason:"Quota unavailable"};
  const limit=quota.storageQuota.limit==null?null:Number(quota.storageQuota.limit),usage=Number(quota.storageQuota.usage??0);
  return {ownerId,email:row.google_account_email??"Google account",connected:true,quotaAvailable:true,limitBytes:limit,usageBytes:usage,remainingBytes:limit==null?null:Math.max(0,limit-usage)};
 }catch(e){return {ownerId,connected:false,reason:"Drive quota lookup failed"}}
}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"POST_REQUIRED"},405);
 let body:any;try{body=await req.json()}catch{return json({error:"INVALID_JSON"},400)}
 const auth=req.headers.get("Authorization")??"",jwt=auth.replace(/^Bearer\s+/i,"");
 if(!jwt||jwt===auth)return json({error:"AUTH_REQUIRED"},401);
 const a=admin();const {data,error}=await a.auth.getUser(jwt);const user=data?.user;
 if(error||!user)return json({error:"INVALID_SESSION"},401);
 if(String(user.email??"").toLowerCase()!==ADMIN_EMAIL)return json({error:"ADMIN_ONLY"},403);
 const action=String(body.action??"dashboard");
 try{
  if(action==="dashboard"){
   const specs=[
    ["projects","wedding_projects"],["studios","photographer_studios"],["albums","wedding_albums"],
    ["invitations","digital_wedding_invitations"],["highlights","wedding_ai_highlight_jobs"],["reels","wedding_reel_exports"]
   ] as const;
   const counts=await Promise.all(specs.map(async([key,table])=>{const {count,error}=await a.from(table).select("id",{count:"exact",head:true});if(error)throw Error("DASHBOARD_QUERY_FAILED");return [key,count??0]}));
   const [{count:orders,error:oe},{data:txs,error:te},{count:activeAlbums,error:ae}] = await Promise.all([
    a.from("wedding_orders").select("id",{count:"exact",head:true}),
    a.from("payment_transactions").select("amount_paise,status").order("created_at",{ascending:false}).limit(5000),
    a.from("wedding_albums").select("id",{count:"exact",head:true}).is("revoked_at",null)
   ]);
   if(oe||te||ae)throw Error("BILLING_QUERY_FAILED");
   const verified=(txs??[]).filter((x:any)=>x.status==="verified");
   return json({ok:true,mode:"development",modules:Object.fromEntries(counts),billing:{orders:orders??0,verifiedPayments:verified.length,pendingPayments:(txs??[]).filter((x:any)=>x.status==="pending").length,revenuePaise:verified.reduce((s:number,x:any)=>s+Number(x.amount_paise??0),0)},activeAlbums:activeAlbums??0});
  }
  if(action==="projects"){
   const {data:rows,error}=await a.from("wedding_projects").select("id,owner_customer_id,title,status,event_date,created_at,updated_at").order("created_at",{ascending:false}).limit(100);
   if(error)throw Error("PROJECT_LIST_FAILED");
   const projects=await Promise.all((rows??[]).map(async(x:any)=>{const {data:u}=await a.auth.admin.getUserById(x.owner_customer_id);return {...x,customerEmail:u.user?.email??"Customer"}}));
   return json({ok:true,projects});
  }
  if(action==="payments"){
   const {data:rows,error}=await a.from("payment_transactions").select("id,order_id,customer_id,gateway,amount_paise,currency,status,verified_at,created_at").order("created_at",{ascending:false}).limit(200);
   if(error)throw Error("PAYMENT_LIST_FAILED");
   const payments=await Promise.all((rows??[]).map(async(x:any)=>{const {data:u}=await a.auth.admin.getUserById(x.customer_id);return {...x,customerEmail:u.user?.email??"Customer"}}));
   return json({ok:true,payments});
  }
  if(action==="audit"){
   const {data:rows,error}=await a.from("wedding_audit_events").select("id,actor_customer_id,project_id,event_type,details,created_at").order("created_at",{ascending:false}).limit(100);
   if(error)throw Error("AUDIT_LIST_FAILED");
   return json({ok:true,events:rows??[]});
  }

  if(action==="support"){
   const {data:rows,error}=await a.from("wedding_support_tickets").select("id,owner_customer_id,project_id,subject,message,status,admin_response,created_at,updated_at").order("created_at",{ascending:false}).limit(200);
   if(error)throw Error("SUPPORT_LIST_FAILED");
   const tickets=await Promise.all((rows??[]).map(async(x:any)=>{const {data:u}=await a.auth.admin.getUserById(x.owner_customer_id);return {...x,customerEmail:u.user?.email??"Customer"}}));
   return json({ok:true,tickets});
  }
  if(action==="support_update"){
   const id=String(body.ticketId??""),status=String(body.status??""),responseText=String(body.adminResponse??"").slice(0,3000);
   if(!/^[0-9a-f-]{36}$/i.test(id)||!["open","in_progress","resolved"].includes(status))return json({error:"INVALID_SUPPORT_UPDATE"},400);
   const {error}=await a.from("wedding_support_tickets").update({status,admin_response:responseText||null,updated_at:new Date().toISOString()}).eq("id",id);
   if(error)throw Error("SUPPORT_UPDATE_FAILED");
   return json({ok:true});
  }
  if(action==="storage"){
   const {data:rows,error}=await a.from("wedding_projects").select("owner_customer_id").order("created_at",{ascending:false}).limit(300);
   if(error)throw Error("STORAGE_OWNERS_FAILED");
   const owners=[...new Set((rows??[]).map((x:any)=>x.owner_customer_id))].slice(0,30);
   const usage=await Promise.all(owners.map((id:string)=>driveQuota(a,id)));
   return json({ok:true,storage:usage});
  }
  return json({error:"ACTION_NOT_SUPPORTED"},400);
 }catch(e){console.error("WEDDING_STUDIO_ADMIN_ERROR",e instanceof Error?e.message:"unknown");return json({error:"ADMIN_QUERY_FAILED"},500)}
});
