import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,apikey,content-type,x-client-info","Access-Control-Allow-Methods":"POST,OPTIONS","Cache-Control":"no-store"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
function admin(){const u=Deno.env.get("SUPABASE_URL"),raw=Deno.env.get("SUPABASE_SECRET_KEYS");let k=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??Deno.env.get("SERVICE_ROLE_KEY");if(!k&&raw){try{k=JSON.parse(raw).default}catch{}}if(!u||!k)throw Error("BACKEND_CONFIG");return createClient(u,k,{auth:{persistSession:false,autoRefreshToken:false}})}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"POST_REQUIRED"},405);
 const key=Deno.env.get("OPENAI_API_KEY");if(!key)return json({error:"AI_PROVIDER_NOT_CONFIGURED"},503);
 const auth=req.headers.get("Authorization")??"",jwt=auth.replace(/^Bearer\s+/i,"");if(!jwt||jwt===auth)return json({error:"AUTH_REQUIRED"},401);
 let body:any;try{body=await req.json()}catch{return json({error:"INVALID_JSON"},400)}
 const projectId=String(body.projectId??""),frames=body.frames;
 if(!/^[0-9a-f-]{36}$/i.test(projectId)||!Array.isArray(frames)||frames.length<3||frames.length>18)return json({error:"INVALID_HIGHLIGHT_INPUT"},400);
 for(const f of frames){if(!Number.isInteger(f.clipIndex)||f.clipIndex<0||!Number.isInteger(f.timestampMs)||f.timestampMs<0||typeof f.imageBase64!=="string"||f.imageBase64.length>350000)return json({error:"INVALID_FRAME"},400)}
 const a=admin(),{data:userData,error:authError}=await a.auth.getUser(jwt),user=userData?.user;
 if(authError||!user)return json({error:"INVALID_SESSION"},401);
 const {data:project,error:projectError}=await a.from("wedding_projects").select("id,owner_customer_id,title").eq("id",projectId).maybeSingle();
 if(projectError||!project)return json({error:"PROJECT_NOT_FOUND"},404);
 if(project.owner_customer_id!==user.id){
  const {data:membership,error:membershipError}=await a.from("wedding_project_invitations")
   .select("id").eq("project_id",projectId).eq("invitee_user_id",user.id)
   .eq("status","accepted").eq("can_view",true).eq("can_edit",true).gt("expires_at",new Date().toISOString()).maybeSingle();
  if(membershipError||!membership)return json({error:"PROJECT_ACCESS_DENIED"},403);
 }
 const {data:job,error:jobError}=await a.from("wedding_ai_highlight_jobs").insert({
  project_id:projectId,owner_customer_id:project.owner_customer_id,source_drive_file_ids:[],status:"processing",
 }).select("id").single();
 if(jobError||!job)return json({error:"JOB_CREATE_FAILED"},500);
 try{
  const content:any[]=[{type:"input_text",text:"You are reviewing sampled still frames from a wedding video project. Select up to 8 visually meaningful moments suitable for a short wedding highlights edit. Prefer ceremony, couple entrances, joyful family moments, candid emotions, decorations and group celebrations. Do not identify people or infer private traits. Return ONLY valid JSON: {\"moments\":[{\"frameIndex\":integer,\"label\":string,\"reason\":string,\"priority\":integer}]}. Each frameIndex must refer to the supplied frame order. Do not invent timestamps; use only frames that show a clear highlight. Avoid duplicate adjacent moments. Project: "+String(project.title??"Wedding")+"."}];
  for(const f of frames)content.push({type:"input_text",text:"Frame "+frames.indexOf(f)+" | clip "+f.clipIndex+" | sampled at "+f.timestampMs+" ms | "+String(f.clipName??"clip")});
  for(const f of frames)content.push({type:"input_image",image_url:"data:image/jpeg;base64,"+f.imageBase64,detail:"low"});
  const response=await fetch("https://api.openai.com/v1/responses",{method:"POST",headers:{"Authorization":"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify({model:"gpt-4.1-mini",input:[{role:"user",content}],max_output_tokens:1200})});
  const result=await response.json();
  if(!response.ok)throw Error("AI_PROVIDER_REQUEST_FAILED");
  const outputText=result.output?.flatMap((x:any)=>x.content??[]).find((x:any)=>x.type==="output_text")?.text??result.output_text;
  if(typeof outputText!=="string")throw Error("AI_EMPTY_RESPONSE");
  const parsed=JSON.parse(outputText.replace(/^\s*```(?:json)?/,"").replace(/```\s*$/,"").trim());
  if(!Array.isArray(parsed.moments))throw Error("AI_RESPONSE_INVALID");
  const moments=parsed.moments.slice(0,8).map((m:any)=>({
    frameIndex:Number(m.frameIndex),label:String(m.label??"Wedding highlight").slice(0,80),
    reason:String(m.reason??"").slice(0,240),priority:Number(m.priority??5),
  })).filter((m:any)=>Number.isInteger(m.frameIndex)&&m.frameIndex>=0&&m.frameIndex<frames.length);
  if(!moments.length)throw Error("NO_HIGHLIGHTS_FOUND");
  const suggested={analysisType:"sampled_frame_visual_analysis",provider:"OpenAI Responses API",moments:moments.map((m:any)=>({...m,clipIndex:frames[m.frameIndex].clipIndex,timestampMs:frames[m.frameIndex].timestampMs,clipDurationMs:frames[m.frameIndex].clipDurationMs,clipName:frames[m.frameIndex].clipName??"Wedding clip"}))};
  const {error:updateError}=await a.from("wedding_ai_highlight_jobs").update({status:"awaiting_approval",suggested_timeline_json:suggested,updated_at:new Date().toISOString()}).eq("id",job.id).eq("owner_customer_id",project.owner_customer_id);
  if(updateError)throw Error("JOB_SAVE_FAILED");
  return json({ok:true,jobId:job.id,suggestedTimeline:suggested});
 }catch(e){
  const message=e instanceof Error?e.message:"AI_ANALYSIS_FAILED";
  await a.from("wedding_ai_highlight_jobs").update({status:"failed",error_code:message,updated_at:new Date().toISOString()}).eq("id",job.id).eq("owner_customer_id",project.owner_customer_id);
  return json({error:message==="AI_PROVIDER_NOT_CONFIGURED"?message:"AI_ANALYSIS_FAILED"},503);
 }
});
