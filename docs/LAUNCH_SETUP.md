# Launch setup checklist

Keep provider secrets out of source code, GitHub files, screenshots and chat.

## 1. Customer account recovery

The app starts with a private Supabase anonymous customer session. Before payment, the customer must add and verify an email address from Account → Protect your account. That email is used to recover the same customer account, order and video after changing or reinstalling a phone.

In Supabase Dashboard:
1. Keep Authentication → Sign In / Providers → Anonymous Sign-Ins enabled.
2. Enable manual identity linking so an anonymous customer can attach a verified email without changing the customer's UUID or losing the order.
3. Enable the Email provider.
4. In Authentication → Email Templates → Email Change, use {{ .Token }} so the account-linking screen receives a six-digit email-change code. In Authentication → Email Templates → Magic Link, also use {{ .Token }} so account recovery sends a six-digit sign-in code. Templates that send only {{ .ConfirmationURL }} send links instead of the codes expected by these screens.
5. Configure production SMTP and test delivery, spam-folder handling, resend limits and OTP expiry.
6. Test Get Started → Account → Protect your account → verify email → pay → reinstall on a test device → Recover account. Confirm the original order and video remain.

Do not let customers pay until a recovery email is verified. Phone-only recovery is not enabled in this app build.

## 2. Google Drive OAuth and encryption

This is separate from customer account recovery. It grants access to the customer's chosen Drive.
1. In Supabase Dashboard → Project Settings → API Keys → Legacy API keys, copy the legacy service_role key and save it as SUPABASE_SERVICE_ROLE_KEY under Project Settings → Edge Functions → Secrets. Do not paste this key into chat or GitHub. The OAuth state RPC and other server-only RPC calls require this legacy service-role JWT; the current logs show the newer sb_secret fallback being used and PostgREST returning PGRST202.
2. Enable the Google Drive API in Google Cloud Console.
2. Set the Drive OAuth web client redirect URI to:
https://mnaswhizatnwfwmjmtvm.supabase.co/functions/v1/google-drive-oauth
3. Before real customers connect Drive, replace GOOGLE_TOKEN_ENCRYPTION_KEY in Supabase Edge Function Secrets with a fresh cryptographically random 32-byte base64 value. Do not reuse the old key or share it in chat.
4. Complete Google's OAuth consent-screen production verification as required.
5. Test Drive connection/return, account email, quota, folder creation, upload and delete on a real Android device.

## 3. Razorpay

1. Use Razorpay test mode first.
2. Set RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET and RAZORPAY_WEBHOOK_SECRET in Supabase Edge Function Secrets.
3. Configure webhook URL:
https://mnaswhizatnwfwmjmtvm.supabase.co/functions/v1/razorpay-payments/webhook
4. Subscribe to payment.captured and payment.failed.
5. Verify a test payment is marked paid only after the server receives the webhook. Use live keys only after this test passes.

## 4. Android release signing and Play listing

- Android application ID: com.weddingvideoshare.app.
- Create a secure Android upload keystore and keep it outside the repository.
- Add GitHub Actions secrets: ANDROID_KEYSTORE_BASE64, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD and ANDROID_STORE_PASSWORD.
- The workflow uses the upload keystore only when all four secrets exist. Otherwise the build uses a development signing key.
- Back up the upload keystore securely.
- Publish the privacy policy and terms at stable public HTTPS URLs. Add a monitored support email/address to both documents and the Play listing.
- Complete screenshots, app icon, content rating, Data safety, target audience and app-access disclosures.

## 5. Real-device acceptance tests

- Link and verify a recovery email, then recover the same account after app data is cleared or the app is reinstalled.
- Test Google Drive OAuth, account email and quota.
- Test ₹290 payment, duplicate-tap protection and webhook verification.
- Interrupt a small upload, reselect the same file and confirm resume.
- Test a large upload near 15 GB on a suitable Drive account.
- Create a private guest link; verify the 6-digit PIN and download on another device.
- Interrupt a guest download and confirm the order does not lock.
- Complete a full transfer and confirm exact expected bytes, customer notification and upload lock.
- Confirm the phone original is untouched and the Drive copy remains until the customer deletes it.
- Test revoked/expired links, incorrect PIN lockout, duplicate webhooks, insufficient Drive quota and expired upload sessions.

The receiver service verifies the byte count streamed by the server. It cannot prove the receiver's device saved the file to disk or independently verify the downloaded file checksum.