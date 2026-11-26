import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,apikey,content-type,x-client-info","Access-Control-Allow-Methods":"POST,OPTIONS","Cache-Control":"no-store"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const ADMIN_EMAIL="ym6250067@gmail.com";
function admin(){const u=Deno.env.get("SUPABASE_URL"),raw=Deno.env.get("SUPABASE_SECRET_KEYS");let k=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??Deno.env.get("SERVICE_ROLE_KEY");if(!k&&raw){try{k=JSON.parse(raw).default}catch{}}if(!u||!k)throw Error("BACKEND_CONFIG");return createClient(u,k,{auth:{persistSession:false,autoRefreshToken:false}})}
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
  return json({error:"ACTION_NOT_SUPPORTED"},400);
 }catch(e){console.error("WEDDING_STUDIO_ADMIN_ERROR",e instanceof Error?e.message:"unknown");return json({error:"ADMIN_QUERY_FAILED"},500)}
});
