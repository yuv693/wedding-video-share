# Firebase Auth and Firestore migration

Target Firebase project: `wedding-video-share`  
Android application ID: `com.weddingvideoshare.app`

## New Firebase foundation in this branch

- Firebase Authentication is the intended customer identity provider.
- Firestore collections are defined for customers, wedding orders, videos, notifications, payment transactions, share links, receiver downloads and audit events.
- Client security rules allow a customer to read only their own account/order/video/notification/payment records.
- Clients cannot write payment status, upload locks, video metadata, share links, download verification or audit events. Those writes must be made by trusted Cloud Functions.
- Callable functions currently provide customer bootstrap, one-order-per-account preparation, account-state retrieval and consent updates.
- Firebase Google Drive endpoints now include `startGoogleDriveOAuth`, `googleDriveOAuthCallback`, `startGoogleDriveUpload`, `resumeGoogleDriveUpload` and `finalizeGoogleDriveUpload`. OAuth state is random, hashed, one-time and expires after 10 minutes. Refresh tokens are encrypted with AES-256-GCM before being stored in the server-only `googleDriveConnections` collection. Upload start is Firebase-ID-token authenticated, owner/order bound, limited to 40 GB, creates a Google Drive resumable session and stores the session URL server-side. A second upload session is rejected while one exists. Finalization independently fetches Drive metadata and only marks the Firestore video uploaded when file ID, filename, MIME type and exact expected byte size match; it then locks the account's single video slot. Razorpay payment is allowed only after that verified upload lock is set. The Flutter app now has an authenticated `FirebaseDriveService` adapter for the Drive HTTP endpoints, and `getGoogleDriveConnection` reports only the signed-in customer's connected email/status. The existing production screen and upload workflow remain on Supabase until the entire Firebase order/payment/share flow is migrated together. The resume endpoint probes Google's resumable session server-side and returns the confirmed next byte offset or completed file ID; share creation, receiver download streaming and consent-based deletion remain outstanding.
- Firebase Razorpay endpoints now include `createRazorpayOrder`, `verifyRazorpayPayment` and the `razorpayWebhook` HTTP endpoint. They enforce ₹290 (29,000 paise), INR, owner-bound gateway orders, explicit Drive auto-delete consent, HMAC payment-signature validation, server-side Razorpay captured-status lookup and idempotent Firestore payment updates. These endpoints are code only until secrets are configured and the backend is deployed.

## Important: staged migration, not cutover

The current production app still calls the legacy Supabase Edge Functions for Google Drive OAuth/upload, Razorpay order creation/webhook verification, share-link creation and receiver download completion. Those endpoints currently authenticate Supabase sessions. Do not remove Supabase Auth, the Supabase Flutter package, the Supabase project, or its Edge Functions until their Firebase Cloud Functions replacements are implemented, deployed and tested end-to-end.

The Firebase functions in this branch are the first server-side Firestore layer; they are not yet a replacement for the existing Drive/payment/share/download backend. The Flutter screens must be switched to these Firebase callables only as each complete flow is migrated. A partial client-side switch would strand existing Supabase customer records and break authorization.

## Firebase Console setup required

1. Confirm Authentication providers: Anonymous and Email/Password. Enable Phone only if phone sign-in is intended.
2. Create/confirm the Cloud Firestore database in production mode. Choose `asia-south1` (Mumbai) for the database location before creating it; Firestore database location cannot be changed later. Callable Functions are configured for `asia-south1` too.
3. Deploy Firestore rules and Cloud Functions from this repository using Firebase CLI.
4. Configure server-side Firebase secrets before deploying payment/Drive endpoints. For Razorpay set `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET` using `firebase functions:secrets:set SECRET_NAME` from a trusted terminal. In the Razorpay dashboard, add the deployed `razorpayWebhook` HTTPS endpoint and subscribe to `payment.captured` (and optionally `payment.failed`). For Google Drive set `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI` (the deployed `googleDriveOAuthCallback` HTTPS URL), and a randomly generated 32-byte base64 `GOOGLE_TOKEN_ENCRYPTION_KEY`. Add the callback URL to the Google OAuth client's authorized redirect URIs. The app must call `startGoogleDriveOAuth` with its Firebase ID token. Never put these values in the Android app, GitHub source, or chat.
5. Firebase Functions deployment may require the Blaze billing plan. Set budget alerts before enabling production functions.
6. Test anonymous account creation, account linking/recovery, owner-only reads, Razorpay order creation + captured-payment signature + webhook replay, Drive OAuth/resumable upload, share PIN, full-byte download verification, and consent-based Drive deletion before cutover.

The Android build workflow compiles the Firebase Functions TypeScript source. The separate manual deployment workflow requires the GitHub secret above. Functions deployment can require the Firebase project to be on the Blaze billing plan; set a budget alert first.

## Existing customer recovery during the bridge

While still signed in on the current phone, open **Account → Protect your account**, verify the existing recovery email if needed, and set the Firebase recovery password. The app links that email/password to the Firebase anonymous account. On a replacement phone, the recovery flow restores the legacy Supabase session with its email code and the Firebase session with the password. A customer who has not linked Firebase on the old phone cannot recover that Firebase identity on a new phone yet.

## Data migration

The current Supabase operational tables were checked before migration: wedding orders, videos, notifications, payment transactions, share links, receiver downloads and audit events are all empty. The Supabase Auth project has 10 identities (9 anonymous and 1 with a confirmed email). Do not copy Supabase password hashes into Firebase. Existing signed-in customers must link a Firebase credential on their current device, or use a deliberate re-verification/reset process.

Existing Supabase customer/order/video IDs must be mapped to Firebase UIDs before production cutover. Do not assume Firebase UIDs equal Supabase user IDs. Export/import must preserve the one-video-per-account rule, payment verification history, Drive OAuth ownership mapping, consent timestamps, share-link state, download attempts and audit records. Keep the old Supabase project intact until reconciliation is complete.
