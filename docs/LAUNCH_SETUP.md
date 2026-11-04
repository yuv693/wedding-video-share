# Launch setup checklist

Keep provider secrets out of source code, GitHub files, screenshots and chat.

## 1. Customer account recovery

The app starts with a private Supabase anonymous customer session. Before uploading or paying, the customer must add and verify an email address from Account → Protect your account. That email is used to recover the same customer account, order and video after changing or reinstalling a phone.

In Supabase Dashboard:
1. Keep Authentication → Sign In / Providers → Anonymous Sign-Ins enabled.
2. Enable manual identity linking so an anonymous customer can attach a verified email without changing the customer's UUID or losing the order.
3. Enable the Email provider.
4. In Authentication → Email Templates → Email Change, use {{ .Token }} so the account-linking screen receives a six-digit email-change code. In Authentication → Email Templates → Magic Link, also use {{ .Token }} so account recovery sends a six-digit sign-in code. Templates that send only {{ .ConfirmationURL }} send links instead of the codes expected by these screens.
5. Configure production SMTP and test delivery, spam-folder handling, resend limits and OTP expiry.
6. Test Get Started → Account → Protect your account → verify email → connect Google Drive → upload one video → Share Video – Pay ₹290 → reinstall on a test device → Recover account. Confirm the original order and video remain.

Do not let customers upload or pay until a recovery email is verified. Phone-only recovery is not enabled in this app build.

## 2. Google Drive OAuth and encryption

This is separate from customer account recovery. It grants access to the customer's chosen Drive.
1. In Supabase Dashboard → Project Settings → API Keys → Legacy API keys, copy the legacy service_role key and save it as SERVICE_ROLE_KEY under Project Settings → Edge Functions → Secrets. Do not paste this key into chat or GitHub. The server functions read this custom secret name because Supabase reserves the SUPABASE_ prefix.
2. Enable the Google Drive API in Google Cloud Console.
3. In Google Auth Platform → Data Access, add the exact scope `https://www.googleapis.com/auth/drive.file` and publish/allow it for the test users. The app requests this scope; if Google's callback returns only `openid` and `email`, Drive access was not granted and upload cannot work.
4. Set the Drive OAuth web client redirect URI to:
https://mnaswhizatnwfwmjmtvm.supabase.co/functions/v1/google-drive-oauth
5. Before real customers connect Drive, replace GOOGLE_TOKEN_ENCRYPTION_KEY in Supabase Edge Function Secrets with a fresh cryptographically random 32-byte base64 value. Do not reuse the old key or share it in chat.
   - Current Supabase logs show Google's `invalid_client` response: the saved `GOOGLE_CLIENT_SECRET` is invalid for the configured OAuth client. Replace it with the current client secret from the same Google Cloud OAuth Web client whose ID is stored as `GOOGLE_CLIENT_ID`; then retry Drive connection. Never paste either secret into chat.
6. Complete Google's OAuth consent-screen production verification as required.
7. Test Drive connection/return, account email, quota, folder creation, upload and delete on a real Android device.

## 3. Razorpay

1. Use Razorpay test mode first.
2. Set RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET and RAZORPAY_WEBHOOK_SECRET in Supabase Edge Function Secrets.
3. Configure webhook URL:
https://mnaswhizatnwfwmjmtvm.supabase.co/functions/v1/razorpay-payments/webhook
4. Subscribe to payment.captured and payment.failed.
5. Verify a test payment is marked paid only after the server receives the webhook. Use live keys only after this test passes.

## 4. Receiver download Worker

The Cloudflare Worker script is `wedding-video-download` on the `weddingvideoshare-ym` workers.dev subdomain. Its public receiver page is:
https://wedding-video-download.weddingvideoshare-ym.workers.dev/

Keep the `DOWNLOAD_WORKER_SECRET` binding configured on that Worker. The Supabase `wedding-share` function redirects paid, valid share links to this exact Worker URL. The worker must call `worker_prepare` and `worker_complete` with the matching secret; verify this on a test share before public launch.

## 5. Android release signing and Play listing

- Android application ID: com.weddingvideoshare.app.
- Create a secure Android upload keystore and keep it outside the repository.
- Add GitHub Actions secrets: ANDROID_KEYSTORE_BASE64, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD and ANDROID_STORE_PASSWORD.
- The workflow uses the upload keystore only when all four secrets exist. Otherwise the build uses a development signing key.
- Back up the upload keystore securely.
- Publish the privacy policy and terms at stable public HTTPS URLs. Add a monitored support email/address to both documents and the Play listing.
- Complete screenshots, app icon, content rating, Data safety, target audience and app-access disclosures.

## 6. Real-device acceptance tests

- Link and verify a recovery email, then recover the same account after app data is cleared or the app is reinstalled.
- Test Google Drive OAuth, account email and quota.
- Test upload first without payment, then ₹290 payment from the Share Video action; confirm the share link appears only after webhook verification.
- Interrupt a small upload, reselect the same file and confirm resume.
- Test a large upload near 40 GB on a suitable Drive account with enough available storage.
- Confirm an unpaid uploaded video cannot create or open a guest share link.
- Create a private guest link; verify the 6-digit PIN and download on another device.
- Interrupt a guest download and confirm the order does not lock and the Drive copy is not deleted.
- Complete a full transfer and confirm exact expected bytes, customer notification and upload lock.
- Confirm the phone original is untouched. Confirm the Drive copy is deleted only when the customer explicitly consented; otherwise it remains.
- Test revoked/expired links, incorrect PIN lockout, duplicate webhooks, insufficient Drive quota and expired upload sessions.

The receiver service verifies the byte count streamed by the server. It cannot prove the receiver's device saved the file to disk or independently verify the downloaded file checksum.
