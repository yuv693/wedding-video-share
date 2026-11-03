# Android release signing — simple Hinglish guide

The current GitHub Actions workflow already supports a real Android upload keystore. Until all four secrets below are added, CI intentionally falls back to a development/debug signing key. That build is for testing only and must not be uploaded to Play Console as the final release.

## Step 1 — Create your own upload keystore on a trusted computer

Install Android Studio / Java 17, then open Terminal (or Windows Command Prompt) in a safe folder OUTSIDE this repository.

Run:

```bash
keytool -genkeypair -v -keystore wedding-video-share-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias weddingvideoshare
```

- Choose a strong keystore password and key password when prompted.
- Keep both passwords private. Do not paste them into ChatGPT, WhatsApp, GitHub files, screenshots, or source code.
- Keep at least two secure backups of `wedding-video-share-upload.jks`. Losing this key can prevent future app updates unless Play App Signing recovery options apply.
- Never commit the JKS file to this repository.

## Step 2 — Convert the keystore to one-line Base64

Linux/macOS:

```bash
base64 -w 0 wedding-video-share-upload.jks
```

macOS alternative:

```bash
base64 < wedding-video-share-upload.jks | tr -d '\n'
```

Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("wedding-video-share-upload.jks"))
```

Copy the complete Base64 output privately.

## Step 3 — Add four GitHub Actions secrets

Open repository:
https://github.com/yuv693/wedding-video-share

Go to **Settings → Secrets and variables → Actions → New repository secret**.
Create these four secrets (names must match exactly):

1. `ANDROID_KEYSTORE_BASE64` = the complete Base64 output from Step 2
2. `ANDROID_KEY_ALIAS` = `weddingvideoshare`
3. `ANDROID_KEY_PASSWORD` = the key password chosen in Step 1
4. `ANDROID_STORE_PASSWORD` = the keystore password chosen in Step 1

Do not send these values in chat. Add them yourself in GitHub's secure Secrets page.

## Step 4 — Build and verify

Open **Actions → Android build → Run workflow** on branch `main`, or push a reviewed code change. Wait for all steps to pass. Download the AAB artifact and verify its signing certificate before uploading it to Play Console.

## Important

- Package/application ID: `com.weddingvideoshare.app`.
- The current successful APK/AAB artifacts were built before these secrets were configured; they are development-signed and are not the final Play Store release.
- Never change or lose the upload keystore after publishing. Back it up securely.
- Google Drive OAuth, Razorpay production credentials/webhook, email SMTP/OTP, privacy/terms publication and real-device acceptance tests remain separate launch requirements.
