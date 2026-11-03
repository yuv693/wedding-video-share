# Wedding Video Share — approved Canva UI mapping

Source design: Canva "Wedding Video Share UI" (design ID: DAHZvpMMlto)
Canvas: 1920 × 1080, 11 pages. The Flutter app must adapt these landscape concept pages to portrait Android screens while preserving the same content hierarchy, ivory/burgundy/gold palette, spacing, rounded panels, and photographic direction.

## Page-to-app mapping

| Canva page | Approved page content | Flutter destination / behavior |
|---|---|---|
| 1 | Wedding Video Share cover; “Share your precious wedding moments with ease” | Brand splash / app identity |
| 2 | Welcome celebration; WVS mark; “Celebrate. Share. Cherish.”; Get Started | Welcome screen; Get Started creates customer session |
| 3 | Welcome back; email/password concept | Account access screen. Keep the implemented email OTP/recovery flow rather than adding password auth without a backend decision |
| 4 | Your Wedding; ₹290 one-wedding plan; 15 GB; Upload Video; Home/Videos/Account | Home dashboard and one-video plan |
| 5 | Upload video (max 15 GB); choose video | Video picker and upload action |
| 6 | Uploading… 45%; pause/resume | Live resumable upload progress |
| 7 | Your Drive. Your storage.; Connect Google Drive | Separate Google Drive OAuth connection and quota |
| 8 | Private share link; Copy Link; Share | Paid share-link and PIN screen |
| 9 | Guest download; Download Wedding Video | Public receiver download page / Worker |
| 10 | Download complete; View Video; Delete Video | Verified completion, view and manual Drive-delete actions |
| 11 | Thank you; Ready to share your special day? | Closing / confirmation state and support information |

## Canva photo assets used

The approved design contains six editable photo fills:

| Page | Canva asset ID | Placement on source canvas |
|---|---|---|
| 1 | MAHZvldZIQE | left 1040, top 0, width 880, height 1080 |
| 2 | MAHZvm3QKNM | left 850, top 0, width 1070, height 1080 |
| 4 | MAHZvqAZMF0 | left 1240, top 750, width 340, height 170 |
| 7 | MAHZvkKD4Ds | left 0, top 0, width 720, height 1080 |
| 9 | MAHZvt2uLL4 | left 0, top 0, width 760, height 1080 |
| 11 | MAHZvpzZr90 | left 1070, top 610, width 850, height 470 |

Canva asset metadata confirms these are wedding/bridal/romance photographs. The Canva connector exposes signed thumbnail URLs and asset metadata, but not downloadable original image bytes. Signed thumbnail URLs expire and must not be embedded in the released app. To package the exact approved photos, export the 11-page Canva design as a PDF (or export the six original images) and add those files to the Flutter repository under `assets/images/`. Then update `pubspec.yaml` and replace the temporary visual placeholders with those local assets.

## Release constraints

- Do not replace the real app's email OTP recovery with a password-only mock screen.
- The ₹290 payment must remain verified by Razorpay webhook before creating a share link.
- The receiver completion state must continue to depend on server-side full-byte transfer verification.
- Keep the video in the customer's own Google Drive; never imply Wedding Video Share supplies the storage.
- The receiver download is a web/Worker flow, not a customer-dashboard screen.
- Do not claim Play Store readiness until the release keystore and live provider configuration are supplied and tested.
