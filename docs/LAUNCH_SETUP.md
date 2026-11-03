# Launch setup checklist

This checklist is for the publisher. Do not put provider secrets in source code, GitHub files, screenshots or chat.

## 1. Google account sign-in (customer identity)

The app's Get Started button uses Google sign-in through Supabase Auth. This is separate from Google Drive authorization.

1. Open the WeddingVideoShare project in Supabase.
2. Go to **Authentication → Sign In / Providers → Google** and enable the Google provider.
3. Create or select a Google OAuth client for the Supabase Auth provider. Use the callback URL shown in the Supabase Google provider setup screen (normally `https://mnaswhizatnwfwmjmtvm.supabase.co/auth/v1/callback`) as an authorized redirect URI in Google Cloud Console.
4. Add the Android app redirect URI `weddingvideoshare://login-callback` to Supabase **Authentication → URL Configuration → Redirect URLs**.
5. Save the Google client ID and client secret only in the Supabase dashboard. Never put the client secret in the Flutter app, GitHub or chat.
6. Test Google sign-in on a real Android device. Confirm the browser returns to the app and the customer session is created.

If the Google provider is not enabled or its credentials/redirects are incorrect, the Google sign-in button will not complete. Provider configuration cannot be confirmed from the app build alone.

## 2. Google Drive OAuth and encryption

This is a second, separate Google authorization. It grants access to the customer's Drive so the wedding video is saved in the customer's own Drive.

1. In Google Cloud Console, confirm the Google Drive API is enabled.
2. Confirm the Drive OAuth web client redirect URI is exactly:
   `https://mnaswhizatnwfwmjmtvm.supabase.co/functions/v1/google-drive-oauth`
3. Before any real customer connects Drive, replace the previously exposed `GOOGLE_TOKEN_ENCRYPTION_KEY` in **Supabase → Edge Functions → Secrets** with a fresh cryptographically random 32-byte base64 value.
4. Do not reuse the old key and do not send the new key in chat or commit it to GitHub.
5. Change the OAuth consent screen from Testing to the appropriate production status and complete any Google verification that Google requires.
6. Test the Drive connect/return flow, account email and quota display on a real Android device.

Rotating the encryption key before customer tokens are stored avoids losing the ability to decrypt tokens created with the previous key.

## 3. Razorpay

1. Create or select the Razorpay account and use test-mode keys first.
2. In Supabase Edge Function Secrets, set `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET`.
3. Add this webhook URL in Razorpay:
   `https://mnaswhizatnwfwmjmtvm.supabase.co/functions/v1/razorpay-payments/webhook`
4. Subscribe to `payment.captured` and `payment.failed`.
5. Complete a test payment and confirm the order becomes paid only after the webhook is received.
6. Only after successful test verification should live keys be used.

## 4. Android and Play Store

- Android application ID: `com.weddingvideoshare.app`. Confirm it is the final package ID before first publication.
- Create a secure Android upload keystore on a trusted computer. Keep the keystore file and passwords outside the repository.
- Add these four GitHub repository Actions secrets under **Settings → Secrets and variables → Actions**:
  - `ANDROID_KEYSTORE_BASE64`: base64-encoded keystore file (encode with `base64 -w 0 upload-keystore.jks` on Linux/macOS; on PowerShell use `[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks"))`).
  - `ANDROID_KEY_ALIAS`: the alias chosen when creating the keystore.
  - `ANDROID_KEY_PASSWORD`: that key's password.
  - `ANDROID_STORE_PASSWORD`: the keystore password.
- The GitHub Actions workflow automatically uses the upload keystore when all four secrets are present. If they are absent, the build is development-signed and must not be uploaded to Play Console.
- Never upload the keystore or passwords to GitHub files, chat or screenshots. Back up the keystore securely; losing it can prevent future app updates.
- Create the Play Store listing, app screenshots, store icon, content rating, data-safety declarations and app-access instructions.
- Publish the privacy policy and terms at stable public HTTPS URLs, and add a monitored support contact to both documents.

## 5. Real-device acceptance tests

Do not publish until these tests pass on real Android devices:

- Google account sign-in and app deep-link return.
- Google Drive OAuth, account email and quota display.
- ₹290 payment, duplicate-tap protection and webhook verification.
- Upload a small video, interrupt the network, reselect the same file and resume.
- Upload a video close to 15 GB on a suitable Drive account.
- Create a private guest link and download from another device.
- Interrupt a guest download and confirm the order does **not** lock.
- Complete a full guest download and confirm the server marks it complete and locks that account's upload.
- Confirm the original phone video remains untouched and the Drive copy remains until the customer deletes it.

The download service verifies full server-observed byte transfer; it does not prove the receiver device saved the file to disk or verify a checksum.
