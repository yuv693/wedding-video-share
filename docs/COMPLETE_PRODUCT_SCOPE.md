# Wedding Video Share — Complete Feature Scope

This product is independent from the user's existing main business. Do not share customers, accounts, databases, storage, payments, or business administration with that business.

## Non-negotiable storage ownership

- Wedding media belongs in the customer's own Google Drive, authorized by that customer through Google OAuth.
- The app must show the connected Google account and available Drive quota before upload.
- The customer's Drive quota is consumed, not a storage bucket owned or paid for by Wedding Video Share.
- Do not put original wedding videos or customer media in a company-owned Firebase Storage or Cloudflare R2 bucket.
- Supabase stores account/order/album metadata and protected OAuth token references only; it is not the media store.
- Any temporary rendering/cache files must be explicitly disclosed, short-lived, and cleaned up. Prefer rendering on the customer's device where practical.
- Never delete the customer's Drive original unless the customer gives clear, separate consent. The default is retain.
- Enforce per-customer access controls; no cross-customer access.

## Existing core workflow to preserve

- One customer account = one wedding share cycle.
- Maximum video size: 40 GB decimal, subject to the customer's available Drive quota.
- ₹290 is charged only when the customer chooses to share.
- Payment is considered complete only after server-side Razorpay webhook verification.
- Guest access is private and protected by a six-digit PIN.
- A share cycle locks only after the server verifies the full receiver transfer.
- The app never deletes the original video from the phone.
- Do not silently change existing price, limits, payment rules, or deletion behavior.

## Product modules to build

1. **Wedding QR Album** — unique QR and private album link; upload/view photos and videos; guest upload permissions configurable by owner.
2. **Photographer & Studio Portal** — studio profile, customer wedding projects, upload handoff, album status, invitations to customers, and project-level access controls.
3. **Wedding Video Studio Editor** — timeline-based editing with clip trim/split/reorder, multiple music tracks, song replacement at a chosen timestamp, audio trim/volume/fade, slow motion, speed-up, transitions, filters, brightness/contrast, text/captions, title/date, and preview.
4. **Save & Export** — persist editable project instructions/timeline so customers can reopen and continue editing; export the final video; preserve the original source. Show progress, handle interruptions, and offer retry.
5. **AI Wedding Highlights** — optional scene/shot selection and highlight assembly, with customer preview and approval before export. Do not claim AI editing is complete until implemented and tested.
6. **Digital Invitations** — editable invitation templates, event details, RSVP/contact link, map/location link, and shareable invitation.
7. **Private Family Albums** — owner-managed guest access, PIN/link protection, revoke/expiry controls, and download permissions.
8. **Admin & Billing** — separate product admin, plans, payment reconciliation, customer support tools, storage/quota visibility, and audit logs. No changes to existing ₹290 price without owner approval.

## Editing and music rights

- Customers can replace a song at any point in the timeline, add multiple tracks, preview, save, reopen, and export.
- Provide only music the customer uploads or music licensed for the product. Do not bundle or promise copyrighted commercial songs without distribution rights.
- Show a clear export estimate and required device storage before rendering.
- Keep source media unchanged; edited output is a new export.

## Security and privacy

- Private-by-default albums and projects.
- Least-privilege Google Drive OAuth scope and encrypted server-side token storage.
- Never expose OAuth tokens, payment secrets, PIN hashes, or private media URLs in the client.
- Validate all access on the server; signed/short-lived access only where needed.
- Explicit consent for guest uploads, downloads, and any deletion.
- Provide account/project deletion and revoke-access flows consistent with retention/legal requirements.

## Delivery stages and acceptance

1. Audit existing app/backend and preserve the current working share/payment/Drive flow.
2. Build customer Drive ownership/quota/permission UX and verify OAuth/upload/resume on real devices.
3. Build QR albums and private family permissions.
4. Build studio portal and project invitations.
5. Build editor timeline, preview, project save/reopen, and export.
6. Add AI highlights and digital invitations.
7. Add admin/billing visibility and complete security/privacy review.
8. Run automated tests plus real Android tests for upload, edit, export, QR, PIN, guest access, payment webhook, revocation, and recovery.

A feature is not complete merely because it appears in the UI or this specification. Mark each module done only after implementation and acceptance tests pass.
