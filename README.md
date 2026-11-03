# Wedding Video Share

Flutter Android app for private wedding-video sharing.

## Product rules
- One paid customer account (₹290) allows one wedding-video upload/share cycle.
- Maximum video size: 15,000,000,000 bytes (15 GB decimal).
- The video is stored in the customer's own Google Drive.
- The app never deletes the original video from the phone.
- Upload locks only after the server verifies the full receiver transfer.
- A new wedding video requires a new account and a new ₹290 payment.

## Current app UI and code paths (not yet end-to-end acceptance-tested)
- Premium wedding-style welcome/onboarding and email/phone OTP sign-in screens.
- Customer dashboard with the ₹290 one-wedding plan, customer-owned Google Drive connection, quota display and 15 GB upload limit.
- Upload progress UI backed by 8 MB Google Drive resumable chunks. If interrupted, the customer reselects the same file to resume from the saved session.
- Private receiver link with a separate 6-digit password.
- Guest download page served by a Cloudflare Worker that streams the file from the customer's Google Drive. It is a page/stream relay only; video storage remains in the customer's Drive, not R2 or app-owner storage.
- Customer notification feed for server-recorded receiver completion, plus a manual control to delete only the Google Drive copy.
- Razorpay ₹290 checkout code; the order remains pending until the server webhook verifies payment.
- GitHub Actions builds an Android App Bundle and installable APK. The workflow uses a development signing key unless all four Android signing secrets are configured. With those secrets, it produces a Play Store upload-signed AAB.

These are implemented code paths and UI, not proof that provider integrations or the full customer journey have passed real-device testing. See the launch checklist below before treating any flow as production-ready.

## Launch checklist
- [Provider setup and Play Store launch checklist](docs/LAUNCH_SETUP.md)

## Legal drafts
- [Privacy Policy](docs/privacy-policy.md)
- [Terms of Service](docs/terms-of-service.md)

These are draft documents. Add a monitored support contact, publish stable public URLs and obtain legal review before release.

## Still required before public launch
- Configure the Supabase email template to include `{{ .Token }}` for numeric email OTP.
- Enable phone authentication and configure a paid SMS provider in Supabase.
- Replace the previously exposed Google token-encryption secret with a fresh random 32-byte base64 key before any real customer connects Google Drive.
- Configure Razorpay keys and webhook in test mode, then run a verified payment test.
- Test Google OAuth, large-file upload/resume, guest download and upload-lock behavior on real Android devices.
- Configure Android release signing, Play Store listing, privacy policy and terms.

The app's client-side payment callback is never treated as proof of payment; the server webhook is authoritative. The receiver download service verifies that the expected number of bytes reached end-of-stream at the server. It does not prove the receiver device saved the file to disk and does not verify a checksum.

## Build
GitHub Actions creates the Android platform folder if absent, configures compile SDK 36 and the Google Drive return link, commits the generated Android project files, then runs `flutter pub get` and `flutter build appbundle --release`. A successful AAB and APK are uploaded as separate workflow artifacts.

## Security
Never commit Supabase service-role keys, Google OAuth client secrets, Google token-encryption keys, Razorpay secrets, or Android signing keystores. Configure secrets only in provider dashboards or GitHub Actions secrets.
