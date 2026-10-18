# TestFlight setup (no Mac needed)

One-time steps the owner does. Builds then go to TestFlight from GitHub Actions, triggered by
**Actions → CI → Run workflow → Upload this build to TestFlight**, or by pushing a `v*` tag. Each
upload waits for the owner's approval of the `release` environment.

Signing material never enters this repository. Keep the files these steps create somewhere
private, outside any git checkout.

## 1. App record in App Store Connect

App Store Connect → Apps → **+** → New App.
- Platform: iOS.
- Name: a store name of your choice. The store name must be unique; the home-screen name stays "Gallery".
- Primary language: your choice.
- Bundle ID: `local-gallery.ios`.
- SKU: any string, for example `local-gallery-ios`.
- User access: Full.

The Account Holder must have accepted the latest agreements (Business → Agreements).

## 2. Distribution certificate, made on archbox

```
mkdir -p ~/apple-signing
chmod 700 ~/apple-signing
cd ~/apple-signing
openssl genrsa -out dist.key 2048
openssl req -new -key dist.key -out dist.csr -subj "/emailAddress=YOUR_APPLE_ACCOUNT_EMAIL/CN=Local Gallery Distribution/C=YOUR_COUNTRY_CODE"
```

Then create the certificate on the developer site:
1. Go to developer.apple.com → Certificates, IDs & Profiles → Certificates → **+**.
2. Choose **Apple Distribution**.
3. Upload `dist.csr`.
4. Download `distribution.cer` into `~/apple-signing`.

Bundle the key and certificate. The export asks for a password; keep it for step 5:

```
openssl x509 -inform DER -in distribution.cer -out dist.pem
openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem -name "Apple Distribution" -out dist.p12
```

## 3. App Store provisioning profile

developer.apple.com → Profiles → **+**:
1. Choose Distribution, **App Store Connect**.
2. Pick the App ID `local-gallery.ios`.
3. Pick the certificate from step 2.
4. Name it, for example `Local Gallery App Store`.
5. Download the `.mobileprovision` file.

## 4. App Store Connect API key (for the upload)

App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → **+**.
- Name: `CI upload`. Access: **App Manager**.
- Download `AuthKey_<KEY_ID>.p8`. Apple offers the download only once.
- Note the **Key ID** and the **Issuer ID** shown on that page.
- Your **Team ID** is on developer.apple.com under Membership details.

## 5. Store everything as GitHub secrets

Run these in your own terminal. Values go straight from files or prompts into GitHub and are
never printed:

```
R=itrap-com/local-gallery-ios
base64 -w0 ~/apple-signing/dist.p12 | gh secret set DIST_CERT_P12_BASE64 --env release --repo "$R"
gh secret set DIST_CERT_P12_PASSWORD --env release --repo "$R"
base64 -w0 PATH/TO/profile.mobileprovision | gh secret set APPSTORE_PROFILE_BASE64 --env release --repo "$R"
gh secret set ASC_KEY_ID --env release --repo "$R"
gh secret set ASC_ISSUER_ID --env release --repo "$R"
gh secret set ASC_KEY_P8 --env release --repo "$R" < PATH/TO/AuthKey_KEYID.p8
gh variable set APPLE_TEAM_ID --repo "$R" --body YOUR_TEAM_ID
```

`gh secret set` without a value prompts for it.

## 6. Upload

1. Trigger the upload: `gh workflow run CI --repo itrap-com/local-gallery-ios -f upload=true`, or use the Run workflow button.
2. Approve the `release` deployment on the run page.
3. The job runs these steps:
   1. archives with the distribution certificate
   2. scans the release binary for networking code and attaches the scan to the run
   3. uploads the build
4. Wait for Apple's processing. App Store Connect sends an email when the build is ready.
5. In App Store Connect → TestFlight, create an **internal** testing group and add yourself.
6. Install the build from the TestFlight app on your iPhone.

TestFlight builds share crash reports with the developer automatically. That runs through Apple, not
through Gallery, and is the only data path a TestFlight build has.
