# Wedding Video Share

Flutter Android app for private wedding-video sharing.

## Product rules
- One customer account is for exactly one wedding video upload/share cycle.
- The video upload is free; ₹290 is charged only when the customer chooses to share.
- Maximum video size: 40,000,000,000 bytes (40 GB decimal).
- The video is stored in the customer's own Google Drive.
- The app never deletes the original video from the phone.
- Upload locks only after the server verifies the full receiver transfer.
- A new wedding video requires a new customer account and a new ₹290 payment.

## Current app flow
1. Welcome page creates a Firebase anonymous identity and a temporary legacy Supabase anonymous session. Google Drive authorization remains a separate OAuth flow.
2. Customer adds and verifies a recovery email before uploading or paying.
3. Customer connects Google Drive separately using Drive OAuth.
4. Customer uploads one video (up to 40 GB) to their own Drive using resumable upload.
5. After upload, the customer taps **Share Video – Pay ₹290**.
6. Razorpay payment is not treated as paid until the server verifies its webhook.
7. Only after payment verification, the app creates a private receiver link and six-digit PIN.
8. The receiver enters the PIN and downloads the video. The server verifies the full streamed byte count.
9. The customer receives a completion notification; the upload slot is locked.
10. The customer may manually delete the Drive copy. The app does not delete it automatically.

## Implementation status
These are implemented UI/code paths, not proof that every third-party integration or the complete journey has passed real-device testing. Firebase Auth/Firestore cutover is not complete; see `docs/FIREBASE_MIGRATION.md`.

- Firebase Authentication creates the customer identity; customers link an email/password to the anonymous Firebase account for cross-device recovery. The legacy Supabase identity remains temporarily active for existing Edge Function authorization.
- Google Drive authorization is a separate OAuth flow.
- Video upload uses resumable chunks and verifies the uploaded file size.
- Razorpay checkout is not considered paid until the server webhook verifies it.
- Receiver completion is based on server-observed full byte transfer. It does not prove the receiver device saved the file to disk or independently verify the downloaded file checksum.
- GitHub Actions builds an Android App Bundle and installable APK. The workflow uses a development signing key unless all four Android signing secrets are configured.
- Flutter widget tests and static analysis run in CI.

## Launch checklist
- [Provider setup and Play Store launch checklist](docs/LAUNCH_SETUP.md)

## Legal drafts
- [Privacy Policy](docs/privacy-policy.md)
- [Terms of Service](docs/terms-of-service.md)

These are draft documents. Add a monitored support contact, publish stable public URLs and obtain legal review before release.

## Still required before public launch
- Finish migrating all Supabase Edge Functions and operational tables to Firebase Cloud Functions and Firestore, then reconcile existing customer IDs before removing Supabase.
- Deploy Firestore security rules and Firebase Functions; enable Firebase Anonymous and Email/Password providers.
- Confirm legacy Supabase anonymous sign-in and six-digit OTP templates during the transition.
- Configure the separate Google Drive OAuth client and verify the Drive callback on Android.
- Replace the Google token-encryption secret with a fresh random 32-byte base64 key before real customers connect Google Drive.
- Configure Razorpay test keys and webhook, then run a verified test payment.
- Test Google sign-in is not used for customer identity; test Google Drive OAuth, large-file upload/resume, guest download and upload-lock behavior on real Android devices.
- Configure Android release signing, Play Store listing, privacy policy and terms.

## Build
GitHub Actions creates the Android platform folder if absent, configures compile SDK 36 and the Google Drive return link, runs Flutter analysis and widget tests, then builds the release AAB and installable APK. A successful AAB and APK are uploaded as separate workflow artifacts.

## Security
Never commit Supabase service-role keys, Google OAuth client secrets, Google token-encryption keys, Razorpay secrets, or Android signing keystores. Configure secrets only in provider dashboards or GitHub Actions secrets.
