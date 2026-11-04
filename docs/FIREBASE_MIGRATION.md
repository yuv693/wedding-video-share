# Firebase Auth and Firestore migration

Target Firebase project: `wedding-video-share`  
Android application ID: `com.weddingvideoshare.app`

## New Firebase foundation in this branch

- Firebase Authentication is the intended customer identity provider.
- Firestore collections are defined for customers, wedding orders, videos, notifications, payment transactions, share links, receiver downloads and audit events.
- Client security rules allow a customer to read only their own account/order/video/notification/payment records.
- Clients cannot write payment status, upload locks, video metadata, share links, download verification or audit events. Those writes must be made by trusted Cloud Functions.
- Callable functions currently provide customer bootstrap, one-order-per-account preparation, account-state retrieval and consent updates.

## Important: staged migration, not cutover

The current production app still calls the legacy Supabase Edge Functions for Google Drive OAuth/upload, Razorpay order creation/webhook verification, share-link creation and receiver download completion. Those endpoints currently authenticate Supabase sessions. Do not remove Supabase Auth, the Supabase Flutter package, the Supabase project, or its Edge Functions until their Firebase Cloud Functions replacements are implemented, deployed and tested end-to-end.

The Firebase functions in this branch are the first server-side Firestore layer; they are not yet a replacement for the existing Drive/payment/share/download backend. The Flutter screens must be switched to these Firebase callables only as each complete flow is migrated. A partial client-side switch would strand existing Supabase customer records and break authorization.

## Firebase Console setup required

1. Confirm Authentication providers: Anonymous and Email/Password. Enable Phone only if phone sign-in is intended.
2. Create/confirm the Cloud Firestore database in production mode.
3. Deploy Firestore rules and Cloud Functions from this repository using Firebase CLI.
4. Configure Google Drive OAuth client ID/secret, 32-byte token-encryption key, Razorpay key ID/secret and webhook secret as server-side Firebase secrets. Never put these values in the Android app, GitHub source, or chat.
5. Firebase Functions deployment may require the Blaze billing plan. Set budget alerts before enabling production functions.
6. Test anonymous account creation, account linking/recovery, owner-only reads, payment webhook verification, Drive OAuth/resumable upload, share PIN, full-byte download verification, and consent-based Drive deletion before cutover.

## Data migration

Existing Supabase customer/order/video IDs must be mapped to Firebase UIDs before production cutover. Do not assume Firebase UIDs equal Supabase user IDs. Export/import must preserve the one-video-per-account rule, payment verification history, Drive OAuth ownership mapping, consent timestamps, share-link state, download attempts and audit records. Keep the old Supabase project intact until reconciliation is complete.
