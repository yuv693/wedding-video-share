# Privacy Policy — Wedding Video Share

**Effective date:** 2 November 2026

This policy explains how Wedding Video Share handles information when you use the app.

## Information we handle

- **Account information:** your email address or mobile number used to sign in through one-time passwords.
- **Google Drive connection:** the Google account email address and an encrypted refresh token needed to upload and stream the video from your own Google Drive.
- **Video information:** filename, file size, MIME type, Google Drive file identifier and upload status. The video itself is stored in your Google Drive, not in Wedding Video Share's own video-storage bucket.
- **Payment information:** order identifiers, payment status, amount, currency and gateway references from Razorpay. Card numbers, UPI PINs and banking passwords are handled by the payment provider and are not requested by this app.
- **Sharing and download records:** share-link records and server-side transfer status, including expected and transferred byte counts, to determine whether a receiver transfer reached the end of the video.
- **Technical information:** service providers may process IP addresses, request timestamps, device/browser details and security logs when you sign in, upload or download.

## How information is used

We use this information to authenticate your account, connect to the Google Drive account you choose, upload your selected video to a Wedding Video Share folder in that Drive, create a private guest link, process the ₹290 payment, stream the video to guests, verify transfer completion and provide customer support.

The app does not delete the original video on your phone. Your Google Drive copy remains in your Drive unless you delete it yourself through Google Drive.

## Google Drive access

When you connect Google Drive, you authorize the app to create and read the video file it manages for this service. The app uses Google Drive to store your video in your own account and stream it to a guest who has your private link. Your Google Drive quota is used. Google handles its own processing under Google's privacy terms.

## Sharing

Anyone who receives an active guest link may be able to download the wedding video. Share the link only with people you trust. The app's download service records whether the full expected number of bytes was streamed by the server. This does not prove that the receiver's device successfully saved the file to disk.

## Service providers

The service uses:
- **Supabase** for authentication, database and server functions.
- **Google** for Google sign-in and Google Drive storage.
- **Razorpay** for payment processing.
- **Cloudflare Workers** to stream the video from Google Drive to a guest.

These providers process information under their own terms and privacy policies.

## Storage and security

Google Drive stores the video in your own account. The service database stores account, payment, video metadata and transfer records needed to operate the service. Google refresh tokens are encrypted before they are stored. We use access controls intended to prevent customers from reading one another's records. No internet service can guarantee absolute security.

## Retention and deletion

Your video remains in your Google Drive until you delete it there. Service records may be retained for account operation, fraud prevention, payment reconciliation, security and legal requirements. To request help with account information or service records, contact the support contact shown in the app's official store listing.

## Your choices

You may choose not to connect Google Drive or not to use the service. You can remove the app's Google access from your Google Account permissions and delete your video directly in Google Drive. Removing access may prevent the app from creating new links or streaming the video.

## Children's privacy

The service is intended for adults managing wedding-video sharing. It is not designed for children to create accounts or make payments.

## Changes and contact

We may update this policy when the service changes. The current policy should be published at the official privacy-policy URL shown in the app listing. For privacy questions, use the support contact published with the app.

**Publication note:** Before public release, the publisher must add a monitored support email/address and publish this policy at a stable public URL. This draft should be reviewed for the laws that apply to the publisher and customers.
