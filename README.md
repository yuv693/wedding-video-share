# Wedding Video Share

Flutter Android app for private wedding-video sharing.

## Product rules
- One paid account (₹290) allows one wedding-video upload/share cycle.
- Maximum video size is 15,000,000,000 bytes (15 GB decimal).
- Video storage belongs to the customer's own Google Drive.
- The app must never delete the phone's original video.
- Upload locks only after the server verifies the complete receiver transfer.
- A new video requires a new account and a new ₹290 payment.

## Current app foundation
- Ivory and burgundy Flutter interface.
- Supabase email OTP and phone OTP sign-in screens.
- Authenticated customer dashboard.
- Google Drive OAuth launch and Android return-link handling.
- Google Drive quota display.
- Razorpay ₹290 checkout launch.
- GitHub Actions workflow for Android App Bundle builds.

## Remaining before launch
- Configure Supabase email OTP and SMS providers.
- Rotate the Google token-encryption secret before any customer connects Drive.
- Configure and test Razorpay credentials and webhook.
- Complete and test large-video upload, private sharing and receiver download on real Android devices.
- Configure Play Store signing and listing.

The app's payment success callback is not treated as proof of payment; the server webhook is authoritative. The download service records full server-observed byte transfer, but does not prove the receiver device saved the file to disk or verify a checksum.

## Build
GitHub Actions creates Android platform files when absent, then runs `flutter pub get` and `flutter build appbundle --release`. A successful build is uploaded as a workflow artifact.

## Security
Never commit service-role keys, OAuth client secrets, token-encryption keys, Razorpay secrets, or signing keystores. Configure secrets only in provider dashboards or GitHub Actions secrets.
