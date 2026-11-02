# Wedding Video Share

Flutter Android app for private wedding-video sharing.

## Product rules
- One paid customer account (₹290) allows one wedding-video upload/share cycle.
- Maximum video size: 15,000,000,000 bytes (15 GB decimal).
- The video is stored in the customer's own Google Drive.
- The app never deletes the original video from the phone.
- Upload locks only after the server verifies the full receiver transfer.
- A new wedding video requires a new account and a new ₹290 payment.

## Implemented app flows
- Ivory and burgundy Flutter interface.
- Supabase email OTP and phone OTP sign-in.
- Authenticated customer dashboard and sign-out.
- Google Drive OAuth connection, Android deep-link return and quota display.
- Razorpay ₹290 checkout; payment remains pending until the server webhook verifies it.
- Android video picker with streaming upload to Google Drive in 8 MB resumable chunks.
- Saved Google Drive upload-session recovery when the customer reselects the same file.
- Server-side file metadata/size verification before creating a private receiver link.
- Copyable private guest link and receiver download service.
- GitHub Actions workflow builds a release Android App Bundle and an installable Android APK, and saves the generated Android project files and dependency lockfile into the repository. The current Android release build uses the debug signing key for development/testing only.

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
