function safeFilename(value) {
  const cleaned = String(value || "wedding-video").replace(/[\\r\\n"]/g, "_").replace(/[^\\w. ()-]/g, "_").slice(0, 180);
  return cleaned || "wedding-video";
}
async function control(env, payload) {
  if (!env.DOWNLOAD_WORKER_SECRET) throw new Error("DOWNLOAD_WORKER_SECRET_MISSING");
  const response = await fetch("https://mnaswhizatnwfwmjmtvm.supabase.co/functions/v1/wedding-share", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "apikey": "sb_publishable_BwuKkASTfQuapaf1vnIAig_6sR9AGpW",
      "x-download-worker-secret": env.DOWNLOAD_WORKER_SECRET
    },
    body: JSON.stringify(payload)
  });
  const data = await response.json().catch(() => null);
  if (!response.ok || !data || data.ok === false) throw new Error(data?.error || "DOWNLOAD_CONTROL_REQUEST_FAILED");
  return data;
}
function page(token, error = "") {
  const safeToken = encodeURIComponent(token);
  const message = error ? '<p class="error">' + error + '</p>' : '';
  return `<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Wedding Video Share</title>
  <style>*{box-sizing:border-box}body{margin:0;min-height:100vh;background:#f7f1eb;color:#33252a;font-family:Arial,sans-serif;display:grid;place-items:center;padding:20px}.card{background:white;width:min(100%,420px);padding:30px;border-radius:22px;box-shadow:0 12px 40px #45202a18;text-align:center}.heart{font-size:34px;color:#6f2438}h1{font-size:24px;color:#6f2438;margin:12px 0}p{line-height:1.5;color:#66575b}.pin{width:100%;padding:16px;border:1px solid #d8c7c3;border-radius:12px;font-size:25px;text-align:center;letter-spacing:10px;margin:12px 0}.btn{width:100%;border:0;background:#6f2438;color:white;padding:16px;border-radius:12px;font-size:16px;font-weight:bold}.error{color:#b42318;font-size:14px}</style>
  <body><main class="card"><div class="heart">♥</div><h1>Your wedding video</h1><p>Enter the 6-digit download password shared with you by the sender.</p>${message}
  <form method="POST" action="/?token=${safeToken}"><input class="pin" name="pin" type="text" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" minlength="6" placeholder="••••••" autocomplete="one-time-code" required><button class="btn" type="submit">Verify & Download</button></form>
  <p style="font-size:12px;line-height:1.5;margin-top:18px">The sender will receive a completion update after the full video transfer is verified. If the sender has agreed, their Google Drive copy is automatically deleted only after the full video has been streamed and the server verifies the complete byte count.</p><p style="font-size:11px;color:#8a7a7d">Wedding Video Share · Keep this password private</p></main></body></html>`;
}
export default {
 async fetch(request, env) {
  const url = new URL(request.url);
  const token = url.searchParams.get("token") || "";
  if (!/^[a-f0-9]{64}$/.test(token)) return new Response("Invalid or expired share link.", {status:404});
  if (request.method === "GET") return new Response(page(token), {headers:{"content-type":"text/html; charset=utf-8","cache-control":"no-store","x-content-type-options":"nosniff"}});
  if (request.method !== "POST") return new Response("Method not allowed.",{status:405});
  let pin = "";
  try { const form = await request.formData(); pin = String(form.get("pin") || ""); } catch (_) {}
  if (!/^\d{6}$/.test(pin)) return new Response(page(token,"Please enter the 6-digit password."),{status:400,headers:{"content-type":"text/html; charset=utf-8","cache-control":"no-store"}});
  let session;
  try { session = await control(env,{action:"worker_prepare",token,pin}); }
  catch (e) {
    const msg = String(e.message || "");
    const userMessage = msg === "PIN_INVALID_OR_LOCKED" ? "Password is incorrect or temporarily locked. Check with the sender." : "This link is invalid or the video is unavailable.";
    return new Response(page(token,userMessage),{status:403,headers:{"content-type":"text/html; charset=utf-8","cache-control":"no-store"}});
  }
  const expected = Number(session.expectedBytes);
  if (!Number.isSafeInteger(expected) || expected <= 0 || expected > 40000000000) {
    await control(env,{action:"worker_complete",downloadId:session.downloadId,shareLinkId:session.shareLinkId,bytesTransferred:0,completed:false}).catch(()=>{});
    return new Response("The video size could not be verified.",{status:502});
  }
  let upstream;
  try {
    upstream = await fetch("https://www.googleapis.com/drive/v3/files/"+encodeURIComponent(session.fileId)+"?alt=media",{headers:{authorization:"Bearer "+session.googleAccessToken}});
  } catch (_) {
    await control(env,{action:"worker_complete",downloadId:session.downloadId,shareLinkId:session.shareLinkId,bytesTransferred:0,completed:false}).catch(()=>{});
    return new Response("Google Drive could not provide the video.",{status:502});
  }
  if (!upstream.ok || !upstream.body || upstream.status !== 200) {
    await control(env,{action:"worker_complete",downloadId:session.downloadId,shareLinkId:session.shareLinkId,bytesTransferred:0,completed:false}).catch(()=>{});
    return new Response("Google Drive could not provide the video.",{status:502});
  }
  const upstreamLength = Number(upstream.headers.get("content-length") || 0);
  if (upstreamLength > 0 && upstreamLength !== expected) {
    await control(env,{action:"worker_complete",downloadId:session.downloadId,shareLinkId:session.shareLinkId,bytesTransferred:0,completed:false}).catch(()=>{});
    return new Response("The video size did not match the saved file.",{status:502});
  }
  const reader=upstream.body.getReader(); let transferred=0; let finished=false;
  const finish=async(completed)=>{
    if(finished)return; finished=true;
    const result=await control(env,{action:"worker_complete",downloadId:session.downloadId,shareLinkId:session.shareLinkId,bytesTransferred:transferred,completed});
    if(completed&&result.completed!==true)throw new Error("DOWNLOAD_COMPLETION_NOT_RECORDED");
  };
  const stream=new ReadableStream({
    async pull(controller){
      try{
        const part=await reader.read();
        if(part.done){
          const complete=transferred===expected; await finish(complete);
          if(complete)controller.close(); else controller.error(new Error("The full video was not streamed."));
          return;
        }
        transferred+=part.value.byteLength;
        if(transferred>expected){await finish(false).catch(()=>{});controller.error(new Error("More bytes than expected."));return;}
        controller.enqueue(part.value);
      }catch(error){await finish(false).catch(()=>{});controller.error(error);}
    },
    async cancel(reason){try{await reader.cancel(reason);}catch(_){} await finish(false).catch(()=>{});}
  });
  return new Response(stream,{status:200,headers:{
    "content-type":session.mimeType||"application/octet-stream",
    "content-length":String(expected),
    "content-disposition":'attachment; filename="'+safeFilename(session.filename)+'"',
    "cache-control":"private, no-store",
    "x-content-type-options":"nosniff"
  }});
 }
};