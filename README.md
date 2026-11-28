# Wedding Video Share

Flutter Android app for private wedding-video sharing and independent wedding tools.

## Product and pricing rules
- The only customer payment is ₹290 for the **Share Video** action.
- Video upload is free.
- Every other Wedding Studio feature/module is free: QR Wedding Album, Photographer Studio Portal, Video Editor, AI Wedding Highlights, Digital Invitations, Family Albums, Wedding Reels, Instagram share/export tools and customer support tools.
- Customers can open and use each feature independently. They do not have to buy or activate a bundle, and there are no per-module or per-feature charges.
- Do not add any additional payment screen, subscription, unlock fee or add-on charge for these modules.
- The ₹290 charge is shown only at the point where the customer chooses to share their uploaded wedding video.
- The app must not claim that a feature is Live until its real backend workflow, permissions and acceptance tests have passed.

## Media and sharing rules
- Maximum video size: 40,000,000,000 bytes (40 GB decimal); actual upload is also limited by available Google Drive quota.
- Customer video media is stored in the customer's own Google Drive; the app stores metadata and editable project data only.
- The app never deletes the original video from the phone.
- The customer must explicitly consent before any Drive copy is deleted. Without consent, retain it.
- Upload locks only after the server verifies the full receiver transfer.
- The ₹290 payment is not treated as paid until the server verifies the Razorpay webhook.
- Only after payment verification, create the private receiver link and six-digit PIN.

## Unified application structure
Keep one Wedding Video Share app and one customer account/workspace. Preserve the existing upload and ₹290 share-payment flow while integrating the older upload/share workflow with the newer Wedding Studio modules. Do not create duplicate app shells, duplicate customer records, or parallel payment systems. Each module must have its own entry point and may be used without opening the other modules.

## Current app flow
1. Welcome page creates a private Supabase anonymous customer session. No Supabase Google sign-in is used.
2. Customer adds and verifies a recovery email before uploading or paying.
3. Customer connects Google Drive separately using Drive OAuth.
4. Customer uploads one video to their own Drive using resumable upload.
5. Customer may use the free Wedding Studio modules independently.
6. When ready to share the uploaded video, the customer taps **Share Video – Pay ₹290**.
7. After verified payment, the app creates a private receiver link and six-digit PIN.
8. The receiver enters the PIN and downloads the video. The server verifies the full streamed byte count.
9. After a complete verified transfer, the upload slot is locked. The Drive copy is deleted only if the customer gave explicit consent; otherwise it is retained.

## Implementation status
Deployed functions and UI routes are not proof that every third-party integration or complete journey has passed real-device testing. Mark modules as Live only after backend, permissions, security and end-to-end acceptance tests pass.

- Supabase Auth creates the customer identity; verified email is used for account recovery.
- Google Drive authorization is a separate OAuth flow.
- Video upload uses resumable chunks and verifies the uploaded file size.
- Razorpay checkout is not considered paid until the server webhook verifies it.
- Receiver completion is based on server-observed full byte transfer. It does not prove the receiver device saved the file to disk or independently verify the downloaded file checksum.
- GitHub Actions builds an Android App Bundle and installable APK. The workflow uses a development signing key unless all four Android signing secrets are configured.
- Flutter widget tests and static analysis run in CI.

## Launch checklist
- [Provider setup and Play Store launch checklist](docs/LAUNCH_SETUP.md)

## Legal and public information pages

- [Privacy Policy](docs/privacy-policy.md)
- [Terms of Service](docs/terms-of-service.md)
- [Cancellation & Refund Policy](docs/cancellation-refund-policy.md)
- [Pricing](docs/pricing.md)
- [About Us](docs/about-us.md)
- [Contact Us](docs/contact-us.md)

The repository also contains a GitHub Pages landing page at `index.html`. These are publication drafts. Add a monitored support email and valid business/correspondence address where required, confirm refund handling, enable GitHub Pages, and obtain legal review before public launch.

## Still required before public launch
- Confirm Supabase anonymous sign-in, manual identity linking, email provider, SMTP and six-digit OTP templates.
- Configure the separate Google Drive OAuth client and verify the Drive callback on Android.
- Replace the Google token-encryption secret with a fresh random 32-byte base64 value before real customers connect Google Drive.
- Configure Razorpay test keys and webhook, then run a verified test payment.
- Test Google Drive OAuth, large-file upload/resume, guest download, consent-based deletion and upload-lock behavior on real Android devices.
- Complete real backend and independent-entry acceptance tests for every free module.
- Configure Android release signing, Play Store listing, privacy policy and terms.

## Build
GitHub Actions creates the Android platform folder if absent, configures compile SDK 36 and the Google Drive return link, runs Flutter analysis and widget tests, then builds the release AAB and installable APK. A successful AAB and APK are uploaded as separate workflow artifacts.

## Security
Never commit Supabase service-role keys, Google OAuth client secrets, Google token-encryption keys, Razorpay secrets, or Android signing keystores. Configure secrets only in provider dashboards or GitHub Actions secrets.
