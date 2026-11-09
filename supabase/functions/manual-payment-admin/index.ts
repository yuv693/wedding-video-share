import { withSupabase } from "npm:@supabase/server@^1";
import { createClient } from "npm:@supabase/supabase-js@2";
const ADMIN_EMAIL="ym6250067@gmail.com";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
const hex=(b:Uint8Array)=>Array.from(b).map(x=>x.toString(16).padStart(2,"0")).join("");
const hash=async(v:string)=>hex(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v))));
function adminClient(){const url=Deno.env.get("SUPABASE_URL");const raw=Deno.env.get("SUPABASE_SECRET_KEYS");let key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??Deno.env.get("SERVICE_ROLE_KEY");if(!key&&raw){try{key=JSON.parse(raw)["default"];}catch{}}if(!url||!key)throw new Error("SERVER_CONFIGURATION_MISSING");return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});}
async function createCustomerShare(admin:any,orderId:string,customerId:string,actorId:string){
 const {data:order,error:oe}=await admin.from("wedding_orders").select("id,customer_id,payment_status").eq("id",orderId).eq("customer_id",customerId).maybeSingle();if(oe||!order||order.payment_status!=="paid")throw new Error("ORDER_NOT_PAID");
 const {data:videos,error:ve}=await admin.from("wedding_videos").select("id,google_drive_file_id,upload_status").eq("order_id",orderId).eq("customer_id",customerId).eq("upload_status","uploaded").is("deleted_at",null);if(ve||!videos||!videos.length||videos.some((v:any)=>!v.google_drive_file_id))throw new Error("VIDEO_NOT_READY");
 const raw=new Uint8Array(32);crypto.getRandomValues(raw);const token=hex(raw);const pb=new Uint32Array(1);crypto.getRandomValues(pb);const pin=String(pb[0]%1000000).padStart(6,"0");const tokenHash=await hash(token),pinHash=await hash(token+":"+pin);
 const {data:old}=await admin.from("share_links").select("id").eq("order_id",orderId).maybeSingle();let saved;
 if(old?.id)saved=await admin.from("share_links").update({token_hash:tokenHash,download_pin_hash:pinHash,download_pin_attempts:0,download_pin_locked_until:null,is_active:true,revoked_at:null,expires_at:null}).eq("id",old.id);
 else saved=await admin.from("share_links").insert({order_id:orderId,token_hash:tokenHash,download_pin_hash:pinHash,download_pin_attempts:0,download_pin_locked_until:null,is_active:true});
 if(saved.error)throw new Error("SHARE_CREATE_FAILED");
 const url=Deno.env.get("SUPABASE_URL")+"/functions/v1/wedding-share?token="+token;
 const message="Your wedding video is ready to share.\n\nPrivate video link:\n"+url+"\n\n6-digit download PIN: "+pin+"\n\nSend the link and PIN to your guests.";
 const {error:ne}=await admin.from("customer_notifications").insert({customer_id:customerId,order_id:orderId,notification_type:"share_ready",title:"Your wedding video link is ready",message});if(ne)throw new Error("CUSTOMER_NOTIFICATION_FAILED");
 await admin.from("audit_events").insert({actor_user_id:actorId,order_id:orderId,event_type:"admin_generated_customer_share",event_data:{video_count:videos.length,reviewed_by:ADMIN_EMAIL}});
 return {shareUrl:url,downloadPin:pin};
}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});if(req.method!=="POST")return json({error:"POST_REQUIRED"},405);
 let body:Record<string,unknown>;try{body=await req.json();}catch{return json({error:"INVALID_JSON"},400);}
 const handler=withSupabase({auth:"user"},async(_request,ctx)=>{
  if(String(ctx.userClaims?.email??"").toLowerCase()!==ADMIN_EMAIL)return json({error:"ADMIN_ONLY"},403);
  const admin=adminClient(),actor=String(ctx.userClaims?.sub??"");
  if(body.action==="list"){
   const {data:txs,error}=await admin.from("payment_transactions").select("id,order_id,customer_id,amount_paise,currency,status,created_at,gateway_payload").eq("gateway","manual_upi").eq("status","pending").order("created_at",{ascending:true}).limit(100);if(error)return json({error:"PAYMENT_LIST_FAILED"},500);
   const rows=await Promise.all((txs??[]).map(async(tx:any)=>{const {data:u}=await admin.auth.admin.getUserById(tx.customer_id);return {...tx,customer_email:u.user?.email??"Guest account"};}));return json({ok:true,payments:rows});
  }
  if(body.action==="dashboard"){
   const [{count:orderCount,error:oe},{count:videoCount,error:ve},{count:activeShares,error:se}] = await Promise.all([
    admin.from("wedding_orders").select("id",{count:"exact",head:true}),
    admin.from("wedding_videos").select("id",{count:"exact",head:true}).is("deleted_at",null),
    admin.from("share_links").select("id",{count:"exact",head:true}).eq("is_active",true).is("revoked_at",null)
   ]);
   if(oe||ve||se)return json({error:"DASHBOARD_LOAD_FAILED"},500);
   const rows:any[]=[];
   for(let offset=0;offset<100000;offset+=1000){
    const {data:page,error}=await admin.from("payment_transactions").select("amount_paise,status").order("created_at",{ascending:true}).range(offset,offset+999);
    if(error)return json({error:"DASHBOARD_LOAD_FAILED"},500);
    rows.push(...(page??[]));
    if(!page||page.length<1000)break;
   }
   const paid=rows.filter((p:any)=>p.status==="verified");
   const pending=rows.filter((p:any)=>p.status==="pending");
   return json({ok:true,stats:{totalRevenuePaise:paid.reduce((s:number,p:any)=>s+(p.amount_paise??0),0),verifiedPayments:paid.length,pendingPayments:pending.length,pendingAmountPaise:pending.reduce((s:number,p:any)=>s+(p.amount_paise??0),0),rejectedPayments:rows.filter((p:any)=>p.status==="failed").length,totalOrders:orderCount??0,totalVideos:videoCount??0,activeShares:activeShares??0}});
  }
  if(body.action==="history"){
   const {data:txs,error}=await admin.from("payment_transactions").select("id,order_id,customer_id,gateway,gateway_order_id,gateway_payment_id,amount_paise,currency,status,verified_at,created_at").order("created_at",{ascending:false}).limit(500);
   if(error)return json({error:"PAYMENT_HISTORY_FAILED"},500);
   const rows=await Promise.all((txs??[]).map(async(tx:any)=>{const {data:u}=await admin.auth.admin.getUserById(tx.customer_id);return {...tx,customer_email:u.user?.email??"Guest account"};}));
   const q=String(body.search??"").trim().toLowerCase();
   return json({ok:true,payments:q?rows.filter((x:any)=>String(x.customer_email).toLowerCase().includes(q)||String(x.id).toLowerCase().includes(q)||String(x.status).toLowerCase().includes(q)):rows});
  }
  if(body.action==="customers"){
   const {data:orders,error}=await admin.from("wedding_orders").select("id,customer_id,amount_paise,payment_status,workflow_status,upload_locked,created_at,updated_at").order("created_at",{ascending:false}).limit(500);
   if(error)return json({error:"CUSTOMER_LIST_FAILED"},500);
   const grouped=new Map<string,any>();
   for(const o of orders??[]){const k=String(o.customer_id);const old=grouped.get(k)??{customer_id:k,orders:0,paid_orders:0,total_paid_paise:0,latest_order_at:o.created_at,latest_status:o.payment_status,workflow_status:o.workflow_status};old.orders++;if(o.payment_status==="paid"){old.paid_orders++;old.total_paid_paise+=o.amount_paise??0;}grouped.set(k,old);}
   const rows=await Promise.all([...grouped.values()].map(async(c:any)=>{const {data:u}=await admin.auth.admin.getUserById(c.customer_id);return {...c,email:u.user?.email??"Guest account",created_at:u.user?.created_at??c.latest_order_at};}));
   const q=String(body.search??"").trim().toLowerCase();
   return json({ok:true,customers:q?rows.filter((x:any)=>String(x.email).toLowerCase().includes(q)||String(x.customer_id).toLowerCase().includes(q)):rows});
  }
  if(body.action==="videos"){
   const {data:videos,error}=await admin.from("wedding_videos").select("id,order_id,customer_id,original_filename,file_size_bytes,upload_status,uploaded_at,created_at,deleted_at").order("created_at",{ascending:false}).limit(500);
   if(error)return json({error:"VIDEO_LIST_FAILED"},500);
   const orderIds=[...new Set((videos??[]).map((v:any)=>v.order_id).filter(Boolean))];
   const customerIds=[...new Set((videos??[]).map((v:any)=>v.customer_id).filter(Boolean))];
   const [{data:orders},{data:users}] = await Promise.all([
    orderIds.length?admin.from("wedding_orders").select("id,payment_status,workflow_status").in("id",orderIds):Promise.resolve({data:[]}),
    Promise.all(customerIds.map(async(id:string)=>{const {data:u}=await admin.auth.admin.getUserById(id);return {id,email:u.user?.email??"Guest account"};})).then(data=>({data}))
   ]);
   const orderMap=new Map((orders??[]).map((o:any)=>[o.id,o]));
   const userMap=new Map((users??[]).map((u:any)=>[u.id,u.email]));
   const rows=(videos??[]).map((v:any)=>({...v,customer_email:userMap.get(v.customer_id)??"Guest account",payment_status:orderMap.get(v.order_id)?.payment_status??"unknown",workflow_status:orderMap.get(v.order_id)?.workflow_status??"unknown"}));
   const q=String(body.search??"").trim().toLowerCase();
   return json({ok:true,videos:q?rows.filter((x:any)=>String(x.customer_email).toLowerCase().includes(q)||String(x.original_filename).toLowerCase().includes(q)||String(x.order_id).toLowerCase().includes(q)):rows});
  }
  if(body.action==="approve"||body.action==="reject"){
   const id=String(body.payment_id??"");if(!/^[0-9a-f-]{36}$/i.test(id))return json({error:"INVALID_PAYMENT_ID"},400);
   const {data:tx,error:le}=await admin.from("payment_transactions").select("id,order_id,customer_id,status,gateway,amount_paise").eq("id",id).eq("gateway","manual_upi").maybeSingle();if(le||!tx)return json({error:"PAYMENT_NOT_FOUND"},404);if(tx.status!=="pending")return json({error:"PAYMENT_NOT_PENDING"},409);
   if(body.action==="reject"){const {error}=await admin.from("payment_transactions").update({status:"failed",gateway_payload:{manual_review:"rejected",reviewed_by:ADMIN_EMAIL,reviewed_at:new Date().toISOString()}}).eq("id",id).eq("status","pending");if(error)return json({error:"REJECT_FAILED"},500);await admin.from("customer_notifications").insert({customer_id:tx.customer_id,order_id:tx.order_id,notification_type:"payment_rejected",title:"Payment request needs attention",message:"Your ₹290 payment request was not approved. Please check your payment receipt and contact support before submitting again."});return json({ok:true,status:"failed"});}
   if(tx.amount_paise!==29000)return json({error:"AMOUNT_MISMATCH"},409);
   const {data:videos,error:ve}=await admin.from("wedding_videos").select("id,google_drive_file_id,upload_status").eq("order_id",tx.order_id).eq("customer_id",tx.customer_id).eq("upload_status","uploaded").is("deleted_at",null);if(ve||!videos?.length||videos.some((v:any)=>!v.google_drive_file_id))return json({error:"VIDEO_NOT_READY"},409);
   const now=new Date().toISOString();const {data:changed,error:ue}=await admin.from("payment_transactions").update({status:"verified",verified_at:now,gateway_payload:{method:"upi_qr",manual_review:"approved",reviewed_by:ADMIN_EMAIL,reviewed_at:now}}).eq("id",id).eq("status","pending").select("id").maybeSingle();if(ue||!changed)return json({error:"PAYMENT_APPROVAL_FAILED"},500);
   const {error:oe}=await admin.from("wedding_orders").update({payment_status:"paid",workflow_status:"video_ready_to_share"}).eq("id",tx.order_id).eq("customer_id",tx.customer_id).eq("payment_status","pending");if(oe){await admin.from("payment_transactions").update({status:"pending",verified_at:null}).eq("id",id);return json({error:"ORDER_UPDATE_FAILED"},500);}
   await admin.from("audit_events").insert({actor_user_id:actor,order_id:tx.order_id,event_type:"manual_upi_payment_approved",event_data:{payment_transaction_id:id,amount_paise:29000,reviewed_by:ADMIN_EMAIL}});
   try{return json({ok:true,status:"verified",...(await createCustomerShare(admin,tx.order_id,tx.customer_id,actor))});}catch(e){return json({ok:true,status:"verified",linkPending:true,linkError:e instanceof Error?e.message:"SHARE_CREATE_FAILED"});}
  }
  if(body.action==="create_link"){const orderId=String(body.order_id??""),customerId=String(body.customer_id??"");if(!/^[0-9a-f-]{36}$/i.test(orderId)||! /^[0-9a-f-]{36}$/i.test(customerId))return json({error:"INVALID_ORDER"},400);try{return json({ok:true,...(await createCustomerShare(admin,orderId,customerId,actor))});}catch(e){return json({error:e instanceof Error?e.message:"SHARE_CREATE_FAILED"},409);}}
  return json({error:"ACTION_NOT_SUPPORTED"},400);
 });return handler(req);
});