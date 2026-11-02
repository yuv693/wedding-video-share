# Wedding Video Share

Flutter Android app foundation for Wedding Video Share.

## Product rules
- One paid account (₹290) permits one wedding-video upload/share cycle.
- Maximum video size: 15,000,000,000 bytes (15 GB decimal).
- Video files are stored in the customer's own Google Drive.
- The app must never delete the phone's original video.
- Upload is locked only after the server verifies a complete receiver transfer.
- A new video requires a new account and a new ₹290 payment.

## Current status
This repository starts the Android Flutter app shell and CI build workflow. It is **not yet a production-ready app**. Authentication, Google Drive OAuth/upload, Razorpay checkout, receiver download, and real-device end-to-end tests still need integration and verification.

## Build
Install Flutter stable, then run:
```sh
flutter pub get
flutter build appbundle --release
```

GitHub Actions runs an Android App Bundle build on pushes and pull requests to `main`. The generated AAB is uploaded as a workflow artifact when the build succeeds.

## Security
Never commit Supabase service-role keys, Google OAuth client secrets, Razorpay secrets, encryption keys, or signing keystores. Configure secrets only in the appropriate provider dashboards / GitHub Actions secrets.
