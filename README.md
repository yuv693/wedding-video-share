# Wedding Video Share

Flutter Android app for private wedding-video sharing.

## Product rules
- One paid customer account (₹290) allows one wedding-video upload/share cycle.
- Maximum video size: 15,000,000,000 bytes (15 GB decimal).
- The video is stored in the customer's own Google Drive.
- The app never deletes the original video from the phone.
- Upload locks only after the server verifies the full receiver transfer.
- A new wedding video requires a new account and a new ₹290 payment.

## Current app flow
1. Welcome page with no email or phone login choices.
2. Get Started opens Google account sign-in, which creates the customer identity.
3. Customer dashboard shows the ₹290 one-video plan before Google Drive authorization.
4. Customer authorizes Google Drive separately; the video is saved to that customer's own Drive.
5. Customer uploads one video (up to 15 GB), with resumable upload progress.
6. App creates a private receiver link and PIN; receiver downloads the video.
7. Server verifies the full transfer and then locks the paid account's upload. Customer sees a completion notification.
8. Customer may manually delete the Drive copy. The app does not delete it automatically.

## Implementation status
These are implemented UI/code paths, not proof that third-party integrations or the complete journey have passed real-device testing. Google sign-in, Drive OAuth, upload, payment, guest download, and server-side completion must all be tested before launch.

- Flutter app uses Supabase Auth for Google identity.
- Google Drive authorization is a separate OAuth flow so the video is stored in the customer's Drive.
- Video upload uses resumable chunks and verifies uploaded file size.
- Razorpay checkout is not considered paid until the server webhook verifies it.
- Receiver completion is determined by server-observed full byte transfer. It does not prove the receiver device saved the file to disk or verify a checksum.
- GitHub Actions builds an Android App Bundle and installable APK. The workflow uses a development signing key unless all four Android signing secrets are configured.

## Launch checklist
- [Provider setup and Play Store launch checklist](docs/LAUNCH_SETUP.md)

## Legal drafts
- [Privacy Policy](docs/privacy-policy.md)
- [Terms of Service](docs/terms-of-service.md)

These are draft documents. Add a monitored support contact, publish stable public URLs and obtain legal review before release.

## Still required before public launch
- Enable and configure the Google provider in Supabase Auth and configure the Android deep-link redirect.
- Configure the separate Google Drive OAuth client and verify the Drive callback.
- Replace the previously exposed Google token-encryption secret with a fresh random 32-byte base64 key before any real customer connects Google Drive.
- Configure Razorpay keys and webhook in test mode, then run a verified payment test.
- Test Google sign-in, large-file upload/resume, guest download and upload-lock behavior on real Android devices.
- Configure Android release signing, Play Store listing, privacy policy and terms.

## Build
GitHub Actions creates the Android platform folder if absent, configures compile SDK 36 and the Google Drive return link, commits the generated Android project files, then builds the release AAB and installable APK. A successful AAB and APK are uploaded as separate workflow artifacts.

## Security
Never commit Supabase service-role keys, Google OAuth client secrets, Google token-encryption keys, Razorpay secrets, or Android signing keystores. Configure secrets only in provider dashboards or GitHub Actions secrets.
