import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Vary": "Origin",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
});
function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  let key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
  if (!key && raw) { try { key = JSON.parse(raw)["default"]; } catch { /* missing key handled below */ } }
  if (!url || !key) throw new Error("BACKEND_CONFIGURATION_MISSING");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
const escapeHtml = (value: unknown) => String(value ?? "").replace(/[&<>"']/g, c => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
}[c]!));
const validSlug = (s: string) => /^[a-z0-9]{16,40}$/.test(s);
const publicUrl = (slug: string) => `${Deno.env.get("SUPABASE_URL")}/functions/v1/wedding-invitation-public?slug=${encodeURIComponent(slug)}`;

async function ownerAction(req: Request, body: Record<string, unknown>) {
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token || token === auth) return json({ error: "AUTH_REQUIRED" }, 401);
  const admin = adminClient();
  const { data: userData, error: authError } = await admin.auth.getUser(token);
  const user = userData?.user;
  if (authError || !user) return json({ error: "INVALID_SESSION" }, 401);
  const invitationId = String(body.invitationId ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(invitationId)) return json({ error: "INVALID_INVITATION" }, 400);
  const { data: invitation, error } = await admin.from("digital_wedding_invitations")
    .select("id,owner_customer_id,public_slug,published_at,rsvp_enabled")
    .eq("id", invitationId).eq("owner_customer_id", user.id).maybeSingle();
  if (error || !invitation) return json({ error: "INVITATION_NOT_FOUND" }, 404);
  if (body.action === "unpublish") {
    const { error: updateError } = await admin.from("digital_wedding_invitations")
      .update({ public_slug: null, published_at: null, updated_at: new Date().toISOString() })
      .eq("id", invitationId).eq("owner_customer_id", user.id);
    if (updateError) return json({ error: "UNPUBLISH_FAILED" }, 500);
    return json({ ok: true, published: false });
  }
  if (body.action !== "publish") return json({ error: "ACTION_NOT_SUPPORTED" }, 400);
  if (!invitation.rsvp_enabled && body.enableRsvp === true) {
    const { error: rsvpError } = await admin.from("digital_wedding_invitations")
      .update({ rsvp_enabled: true, updated_at: new Date().toISOString() })
      .eq("id", invitationId).eq("owner_customer_id", user.id);
    if (rsvpError) return json({ error: "RSVP_SETTING_FAILED" }, 500);
  }
  const slug = invitation.public_slug && validSlug(invitation.public_slug)
    ? invitation.public_slug
    : Array.from(crypto.getRandomValues(new Uint8Array(16))).map(x => x.toString(16).padStart(2, "0")).join("");
  const { error: updateError } = await admin.from("digital_wedding_invitations")
    .update({ public_slug: slug, published_at: new Date().toISOString(), updated_at: new Date().toISOString() })
    .eq("id", invitationId).eq("owner_customer_id", user.id);
  if (updateError) return json({ error: "PUBLISH_FAILED" }, 500);
  return json({ ok: true, published: true, slug, publicUrl: publicUrl(slug) });
}

async function renderInvitation(slug: string, received: boolean) {
  if (!validSlug(slug)) return new Response("Invitation not found", { status: 404 });
  const admin = adminClient();
  const { data: invitation, error } = await admin.from("digital_wedding_invitations")
    .select("id,title,template_key,event_details,rsvp_enabled,published_at,public_slug")
    .eq("public_slug", slug).not("published_at", "is", null).maybeSingle();
  if (error || !invitation) return new Response("Invitation not found or unpublished.", {
    status: 404, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
  const d = invitation.event_details ?? {};
  const couple = [d.bride, d.groom].filter(Boolean).map(escapeHtml).join(" & ");
  const language = ["gu", "hi", "ur", "en"].includes(String(d.language)) ? String(d.language) : "en";
  const isRtl = language === "ur";
  const familyHosts = escapeHtml(d.family_hosts);
  const customMessage = escapeHtml(d.custom_message);
  const optionalWording = escapeHtml(d.optional_religious_wording);
  const musicUrl = typeof d.music_url === "string" && /^https:\/\//i.test(d.music_url) ? d.music_url : "";
  const musicHtml = musicUrl ? `<section class="music"><p>Wedding music</p><audio controls preload="none" src="${escapeHtml(musicUrl)}"></audio></section>` : "";
  const photoUrl = typeof d.photo_url === "string" &&
    /^https:\/\/mnaswhizatnwfwmjmtvm\.supabase\.co\/storage\/v1\/object\/public\/wedding-invitation-assets\/[A-Za-z0-9_./-]+$/i.test(d.photo_url)
    ? d.photo_url : "";
  const photoHtml = photoUrl ? `<img class="hero-photo" src="${escapeHtml(photoUrl)}" alt="Wedding couple">` : "";
  const localeText: Record<string, { together: string; rsvp: string; name: string; email: string; attend: string; yes: string; no: string; count: string; message: string; submit: string }> = {
    en: { together: "Together with their families", rsvp: "Will you be joining us?", name: "Your name", email: "Email (optional)", attend: "Will you attend?", yes: "Joyfully accept", no: "Regretfully decline", count: "Number of guests", message: "Message (optional)", submit: "Send RSVP" },
    gu: { together: "પરિવાર સાથે", rsvp: "શું તમે અમારી સાથે જોડાશો?", name: "તમારું નામ", email: "ઈમેલ (વૈકલ્પિક)", attend: "તમે હાજર રહેશો?", yes: "હા, આનંદથી", no: "માફ કરશો, આવી શકીશ નહીં", count: "મહેમાનોની સંખ્યા", message: "સંદેશ (વૈકલ્પિક)", submit: "જવાબ મોકલો" },
    hi: { together: "परिवार सहित", rsvp: "क्या आप हमारे साथ शामिल होंगे?", name: "आपका नाम", email: "ईमेल (वैकल्पिक)", attend: "क्या आप आएँगे?", yes: "हाँ, खुशी से", no: "क्षमा करें, नहीं आ सकूँगा", count: "मेहमानों की संख्या", message: "संदेश (वैकल्पिक)", submit: "जवाब भेजें" },
    ur: { together: "اپنے خاندانوں کے ساتھ", rsvp: "کیا آپ ہمارے ساتھ شامل ہوں گے؟", name: "آپ کا نام", email: "ای میل (اختیاری)", attend: "کیا آپ تشریف لائیں گے؟", yes: "خوشی سے قبول", no: "معذرت، حاضر نہیں ہو سکوں گا", count: "مہمانوں کی تعداد", message: "پیغام (اختیاری)", submit: "جواب بھیجیں" },
  };
  const localized = localeText[language] ?? localeText.en;
  const title = escapeHtml(invitation.title || "Wedding Invitation");
  const eventList = Array.isArray(d.functions) && d.functions.length
    ? d.functions.slice(0, 12)
    : [{ name: d.function_name, date_time: d.date_time, venue: d.venue, address: d.address, map_link: d.map_link }];
  const eventHtml = eventList.map((event: any) => {
    const name = escapeHtml(event.name ?? event.function_name ?? "Wedding celebration");
    const eventDate = escapeHtml(event.date_time ?? d.date_time);
    const eventVenue = escapeHtml(event.venue ?? d.venue);
    const eventAddress = escapeHtml(event.address ?? d.address);
    const eventMap = typeof (event.map_link ?? d.map_link) === "string" && /^https:\/\//i.test(event.map_link ?? d.map_link)
      ? String(event.map_link ?? d.map_link) : "";
    return `<section class="event"><h2>${name}</h2>${eventDate ? `<p>${eventDate}</p>` : ""}${eventVenue ? `<p>${eventVenue}</p>` : ""}${eventAddress ? `<p>${eventAddress}</p>` : ""}${eventMap ? `<a class="map" href="${escapeHtml(eventMap)}" rel="noopener noreferrer">View venue map</a>` : ""}</section>`;
  }).join("");
  const community = escapeHtml(d.community);
  const presentationStyle = String(d.presentation_style ?? "classic_card");
  const modern = invitation.template_key === "modern_editorial";
  const map = typeof d.map_link === "string" && /^https:\/\//i.test(d.map_link) ? d.map_link : "";
  // Each selected tradition now has its own palette and visual treatment rather
  // than falling back to one generic pink card.
  const templateThemes: Record<string, { accent: string; paper: string; border: string; ornament: string }> = {
    hindu_traditional: { accent: "#9b3f18", paper: "#fff5e5", border: "#d9a441", ornament: "double" },
    muslim_nikah: { accent: "#17634f", paper: "#f2f8f2", border: "#b99a57", ornament: "geometric" },
    muslim_walima: { accent: "#315c55", paper: "#f6f4ed", border: "#c2a66b", ornament: "geometric" },
    sikh_anand_karaj: { accent: "#9a5a18", paper: "#fff7e9", border: "#d7ad62", ornament: "double" },
    christian_classic: { accent: "#405d7a", paper: "#f5f7fb", border: "#b7c4d4", ornament: "classic" },
    jain_traditional: { accent: "#8b4b27", paper: "#fff8ed", border: "#d8b36b", ornament: "classic" },
    buddhist_traditional: { accent: "#8b5b20", paper: "#fff8e8", border: "#d9b45c", ornament: "classic" },
    parsi_traditional: { accent: "#7b3e3e", paper: "#fff6f2", border: "#c99b83", ornament: "classic" },
    custom_minimal: { accent: "#46535d", paper: "#f7f8f8", border: "#cbd1d5", ornament: "minimal" },
    modern_editorial: { accent: "#6b5a4a", paper: "#f5eee5", border: "#c5ae91", ornament: "editorial" },
  };
  const selectedTheme = templateThemes[String(invitation.template_key)] ??
    { accent: "#7a4055", paper: "#fffafa", border: "#eadbd6", ornament: "classic" };
  const theme = selectedTheme.accent;
  const paper = selectedTheme.paper;
  const ornament = selectedTheme.ornament;
  const rsvp = invitation.rsvp_enabled ? `
    <section class="rsvp"><h2>${localized.rsvp}</h2>
      ${received ? '<p class="success">Thank you. Your RSVP has been received.</p>' : `
      <form method="post" action="?slug=${encodeURIComponent(slug)}">
        <label>${localized.name}<input name="guest_name" required maxlength="100" autocomplete="name"></label>
        <label>${localized.email}<input name="guest_email" type="email" maxlength="254" autocomplete="email"></label>
        <label>${localized.attend}
          <select name="attending"><option value="yes">${localized.yes}</option><option value="no">${localized.no}</option></select>
        </label>
        <label>${localized.count}<input name="guest_count" type="number" min="1" max="10" value="1" required></label>
        <label>${localized.message}<textarea name="message" maxlength="500"></textarea></label>
        <button type="submit">${localized.submit}</button>
      </form>`}
    </section>` : "";
  const modernCss = modern ? `.wrap{max-width:760px;margin:0 auto;padding:clamp(18px,5vw,48px)}.card{position:relative;overflow:hidden;border:0;border-radius:2px;padding:clamp(36px,8vw,82px) clamp(22px,7vw,70px);background:linear-gradient(145deg,#fffefa,#f5eee5);box-shadow:0 18px 60px #3b30221a;animation:arrive .9s ease both}.card:before,.card:after{content:"";position:absolute;pointer-events:none;border:1px solid #c5ae91;inset:12px}.card:after{inset:18px;border-color:#e5d8c8}.eyebrow{letter-spacing:.28em;font:11px Arial;color:#8b735d}.couple{font-family:Georgia,serif;font-weight:400;letter-spacing:-.035em;line-height:1.12;color:#4e4035;margin:30px 0}.detail{font:15px/1.9 Arial;color:#71665b}.event{padding:16px 0;border-top:1px solid #e5d8c8;font:15px/1.8 Arial;color:#71665b}.event h2{font:20px Georgia,serif;color:#4e4035}.rsvp{border-top:1px solid #dfd2c3}.rsvp h2{font-weight:400;letter-spacing:.03em}@keyframes arrive{from{opacity:0;transform:translateY(18px)}to{opacity:1;transform:translateY(0)}}` : "";
  const scrollingCss = presentationStyle === "scrolling_webpage" ? `.wrap{max-width:860px}.card{padding:clamp(30px,6vw,64px);text-align:center}.detail{max-width:680px;margin:24px auto}.event{margin:18px 0;padding:24px;background:#fffdf9;border:1px solid #e9ddcf;border-radius:14px;text-align:left}.event h2{font-size:24px}` : "";
  const cinematicCss = presentationStyle === "cinematic_animated" ? `.card{animation:arrive 1.1s ease both}.eyebrow{animation:arrive 1.4s ease both}.couple{animation:arrive 1.7s ease both}` : "";
  const html = `<!doctype html><html lang="${language}" dir="${isRtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><meta name="theme-color" content="${theme}"><title>${title}</title>
  <style>body{margin:0;background:${paper};color:#33252a;font-family:Georgia,"Noto Naskh Arabic","Noto Sans Gujarati","Noto Sans Devanagari",serif;direction:${isRtl ? "rtl" : "ltr"};text-align:${isRtl ? "right" : "center"}.wrap{max-width:620px;margin:32px auto;padding:16px}.card{position:relative;background:${paper};border:2px solid ${selectedTheme.border};border-radius:${ornament==="minimal"?"8px":"24px"};padding:32px 24px;text-align:center;box-shadow:0 12px 40px #39231a12}.card:before{content:"";display:block;height:5px;max-width:180px;margin:0 auto 22px;background:${selectedTheme.border};border-radius:10px}.card:after{content:"";display:block;height:1px;max-width:110px;margin:24px auto 0;background:${selectedTheme.border}}.eyebrow{letter-spacing:.18em;text-transform:uppercase;color:${theme};font:12px Arial}.couple{font-size:clamp(30px,7vw,48px);color:${theme};margin:22px 0}.detail{font:16px/1.7 Arial;color:#5b5050}.event{padding:16px 0;border-top:1px solid ${selectedTheme.border};font:15px/1.8 Arial;color:#5b5050}.event h2{font:20px Georgia,serif;color:${theme}}.map{display:inline-block;margin:12px;color:${theme}}.rsvp{margin:28px auto 0;text-align:left;max-width:460px;border-top:1px solid ${selectedTheme.border};padding-top:20px}.rsvp h2{text-align:center;color:${theme}}label{display:block;font:14px Arial;margin:14px 0}input,select,textarea{display:block;box-sizing:border-box;width:100%;padding:12px;margin-top:6px;border:1px solid #d8c9c4;border-radius:9px;font:16px Arial}button{width:100%;padding:14px;border:0;border-radius:10px;background:${theme};color:white;font-weight:bold;font-size:16px}.success{background:#e8f4ea;color:#215b30;padding:14px;border-radius:10px;text-align:center;font:15px Arial}.footer{font:12px Arial;color:#8b7e7a;text-align:center;margin:20px}.hero-photo{display:block;width:100%;max-height:420px;object-fit:cover;border-radius:16px;margin:22px auto}.music{margin:22px auto}.music audio{width:100%;max-width:420px}.print-btn{margin:22px auto 0;max-width:240px;display:block}.print-btn:hover{opacity:.9}@media print{body{background:white}.wrap{margin:0;max-width:none}.card{box-shadow:none;break-inside:avoid}.print-btn,.rsvp form{display:none}}${ornament==="geometric"?".card{background-image:linear-gradient(45deg,transparent 48%,#17634f0b 49%,#17634f0b 51%,transparent 52%);background-size:22px 22px}":""}${ornament==="double"?".card{outline:1px solid "+selectedTheme.border+";outline-offset:5px}":""}${modernCss}${scrollingCss}${cinematicCss}</style></head>
  <body><main class="wrap"><article class="card"><div class="eyebrow">${community || localized.together}</div><h1>${title}</h1>${photoHtml}<div class="couple">${couple || title}</div>${familyHosts ? `<p class="detail">${familyHosts}</p>` : ""}${optionalWording ? `<p class="detail">${optionalWording}</p>` : ""}<div class="detail">${eventHtml}</div>${customMessage ? `<p class="detail">${customMessage}</p>` : ""}${musicHtml}${rsvp}<button class="print-btn" type="button" onclick="window.print()">Print / Save as PDF</button></article><p class="footer">Wedding Video Share • Private invitation link</p></main></body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY", "Referrer-Policy": "no-referrer", "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'" } });
}

async function submitRsvp(req: Request, slug: string) {
  if (!validSlug(slug)) return new Response("Invitation not found", { status: 404 });
  const form = new URLSearchParams(await req.text());
  const guestName = (form.get("guest_name") ?? "").trim();
  const guestEmail = (form.get("guest_email") ?? "").trim().toLowerCase();
  const attending = form.get("attending") === "yes";
  const count = Number(form.get("guest_count") ?? "1");
  const message = (form.get("message") ?? "").trim();
  if (!guestName || guestName.length > 100 || guestEmail.length > 254 ||
      (guestEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(guestEmail)) ||
      !Number.isInteger(count) || count < 1 || count > 10 || message.length > 500) {
    return new Response("Please check your RSVP details and try again.", { status: 400, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }
  const admin = adminClient();
  const { data: invitation, error } = await admin.from("digital_wedding_invitations")
    .select("id,rsvp_enabled").eq("public_slug", slug).not("published_at", "is", null).maybeSingle();
  if (error || !invitation || !invitation.rsvp_enabled) return new Response("RSVP is unavailable for this invitation.", { status: 404 });
  const { error: insertError } = await admin.from("wedding_invitation_rsvps").insert({
    invitation_id: invitation.id, guest_name: guestName, guest_email: guestEmail || null,
    attending, guest_count: count, message: message || null,
  });
  if (insertError) {
    console.error("INVITATION_RSVP_INSERT_FAILED", insertError.code ?? "unknown");
    return new Response("We could not save your RSVP. Please try again later.", { status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }
  return Response.redirect(publicUrl(slug) + "&rsvp=received", 303);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);
  const slug = url.searchParams.get("slug") ?? "";
  if (req.method === "GET") return await renderInvitation(slug, url.searchParams.get("rsvp") === "received");
  if (req.method === "POST") {
    if ((req.headers.get("content-type") ?? "").includes("application/x-www-form-urlencoded")) {
      return await submitRsvp(req, slug);
    }
    let body: Record<string, unknown>;
    try { body = await req.json(); } catch { return json({ error: "INVALID_JSON" }, 400); }
    return await ownerAction(req, body);
  }
  return json({ error: "METHOD_NOT_ALLOWED" }, 405);
});
