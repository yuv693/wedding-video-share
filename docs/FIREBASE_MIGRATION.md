# Firebase Auth and Firestore migration

Target Firebase project: `wedding-video-share`  
Android application ID: `com.weddingvideoshare.app`

## New Firebase foundation in this branch

- Firebase Authentication is the intended customer identity provider.
- Firestore collections are defined for customers, wedding orders, videos, notifications, payment transactions, share links, receiver downloads and audit events.
- Client security rules allow a customer to read only their own account/order/video/notification/payment records.
- Clients cannot write payment status, upload locks, video metadata, share links, download verification or audit events. Those writes must be made by trusted Cloud Functions.
- Callable functions currently provide customer bootstrap, one-order-per-account preparation, account-state retrieval and consent updates.
- Firebase Google Drive endpoints now include `startGoogleDriveOAuth`, `googleDriveOAuthCallback`, `startGoogleDriveUpload`, `resumeGoogleDriveUpload` and `finalizeGoogleDriveUpload`. OAuth state is random, hashed, one-time and expires after 10 minutes. Refresh tokens are encrypted with AES-256-GCM before being stored in the server-only `googleDriveConnections` collection. Upload start is Firebase-ID-token authenticated, owner/order bound, limited to 40 GB, creates a Google Drive resumable session and stores the session URL server-side. A second upload session is rejected while one exists. Finalization independently fetches Drive metadata and only marks the Firestore video uploaded when file ID, filename, MIME type and exact expected byte size match; it then locks the account's single video slot. Razorpay payment is allowed only after that verified upload lock is set. The Flutter app has authenticated `FirebaseDriveService` and `FirebaseWeddingService` adapters, a Firebase-aware resumable upload implementation, and a Home screen wired to Firebase for account state, Drive OAuth, upload, consent, Razorpay order/payment verification and share-link creation. `getGoogleDriveConnection` reports only the signed-in customer's connected email/status. The onboarding Drive OAuth step also uses Firebase. The resume endpoint probes Google's resumable session server-side and returns the confirmed next byte offset or completed file ID. Firebase share endpoints now create a random private link and six-digit PIN, enforce a five-attempt/15-minute lock, verify paid order + active consent + Drive file size, create receiver download sessions, and accept completion only from the Cloudflare worker secret endpoint. On a full server-reported byte count, the backend rechecks consent and download state before deleting the Drive copy. The Cloudflare worker in this branch now calls the Firebase worker-control endpoint; it still needs its DOWNLOAD_WORKER_SECRET environment variable set to the same Firebase secret.
- Firebase Razorpay endpoints now include `createRazorpayOrder`, `verifyRazorpayPayment` and the `razorpayWebhook` HTTP endpoint. They enforce ₹290 (29,000 paise), INR, owner-bound gateway orders, explicit Drive auto-delete consent, HMAC payment-signature validation, server-side Razorpay captured-status lookup and idempotent Firestore payment updates. These endpoints are code only until secrets are configured and the backend is deployed.

## Important: staged migration, not cutover

The main customer workflow now uses Firebase Cloud Functions and Firestore. Supabase remains intentionally installed for the legacy email verification/account recovery bridge and any existing customer records. The Firebase backend and Cloudflare worker have not yet been deployed and tested end-to-end, so this is not a production cutover. Do not remove Supabase Auth, the Supabase project, or its Edge Functions until identity recovery, existing-customer mapping, receiver download, payment webhook replay and consent-based deletion have all been verified in production-like tests.

The Home screen still requires the legacy Supabase email verification to protect account recovery while the Firebase identity link is in place. Manual Drive-copy deletion was removed from the Home UI; the supported automatic deletion path remains gated by explicit consent and verified full-byte receiver transfer.

## Firebase Console setup required

1. Confirm Authentication providers: Anonymous and Email/Password. Enable Phone only if phone sign-in is intended.
2. Create/confirm the Cloud Firestore database in production mode. Choose `asia-south1` (Mumbai) for the database location before creating it; Firestore database location cannot be changed later. Callable Functions are configured for `asia-south1` too.
3. Deploy Firestore rules and Cloud Functions from this repository using Firebase CLI.
4. Configure server-side Firebase secrets before deploying payment/Drive endpoints. For Razorpay set `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET` using `firebase functions:secrets:set SECRET_NAME` from a trusted terminal. In the Razorpay dashboard, add the deployed `razorpayWebhook` HTTPS endpoint and subscribe to `payment.captured` (and optionally `payment.failed`). For Google Drive set GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI (the deployed googleDriveOAuthCallback HTTPS URL), and a randomly generated 32-byte base64 GOOGLE_TOKEN_ENCRYPTION_KEY. For receiver downloads set a long random DOWNLOAD_WORKER_SECRET in Firebase Functions and the identical value as a Cloudflare Worker secret. Add the callback URL to the Google OAuth client's authorized redirect URIs. The app must call `startGoogleDriveOAuth` with its Firebase ID token. Never put these values in the Android app, GitHub source, or chat.
5. Firebase Functions deployment may require the Blaze billing plan. Set budget alerts before enabling production functions.
6. Test anonymous account creation, account linking/recovery, owner-only reads, Razorpay order creation + captured-payment signature + webhook replay, Drive OAuth/resumable upload, share PIN, full-byte download verification, and consent-based Drive deletion before cutover.

The Android build workflow compiles the Firebase Functions TypeScript source. The separate manual deployment workflow requires the GitHub secret above. Functions deployment can require the Firebase project to be on the Blaze billing plan; set a budget alert first.

## Existing customer recovery during the bridge

While still signed in on the current phone, open **Account → Protect your account**, verify the existing recovery email if needed, and set the Firebase recovery password. The app links that email/password to the Firebase anonymous account. On a replacement phone, the recovery flow restores the legacy Supabase session with its email code and the Firebase session with the password. A customer who has not linked Firebase on the old phone cannot recover that Firebase identity on a new phone yet.

## Data migration

The current Supabase operational tables were checked before migration: wedding orders, videos, notifications, payment transactions, share links, receiver downloads and audit events are all empty. The Supabase Auth project has 10 identities (9 anonymous and 1 with a confirmed email). Do not copy Supabase password hashes into Firebase. Existing signed-in customers must link a Firebase credential on their current device, or use a deliberate re-verification/reset process.

Existing Supabase customer/order/video IDs must be mapped to Firebase UIDs before production cutover. Do not assume Firebase UIDs equal Supabase user IDs. Export/import must preserve the one-video-per-account rule, payment verification history, Drive OAuth ownership mapping, consent timestamps, share-link state, download attempts and audit records. Keep the old Supabase project intact until reconciliation is complete.
