# TestFlight setup (no Mac needed)

One-time steps the owner does. Builds then go to TestFlight from GitHub Actions, triggered by
**Actions → CI → Run workflow → Upload this build to TestFlight**, or by pushing a `v*` tag. Each
upload waits for the owner's approval of the `release` environment.

Signing material never enters this repository. Keep the files these steps create somewhere
private, outside any git checkout.

## 1. App record in App Store Connect

App Store Connect → Apps → **+** → New App.
- Platform: iOS.
- Name: a store name of your choice. The store name must be unique. Use "Local Gallery": the app's display name is the same, and App Store processing rejects a display name that another app has taken (ITMS-90129).
- Primary language: your choice.
- Bundle ID: `Local-gallery.ios`.
- SKU: any string, for example `local-gallery-ios`.
- User access: Full.

The Account Holder must have accepted the latest agreements (Business → Agreements).

## 2. App Store Connect API key (it also signs)

There is no certificate or profile to make. The upload job archives unsigned, and the export signs
with Apple's cloud-managed distribution certificate, using this key.

App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → **+**.
- Name: `CI upload`. Access: **Admin** (cloud-managed signing needs it; App Manager cannot sign).
- Download `AuthKey_<KEY_ID>.p8`. Apple offers the download only once.
- Note the **Key ID** and the **Issuer ID** shown on that page.
- Your **Team ID** is on developer.apple.com under Membership details.

## 3. Store it as GitHub secrets

Run these in your own terminal. Values go straight from files or prompts into GitHub and are
never printed:

```
R=itrap-com/local-gallery-ios
gh secret set ASC_KEY_ID --env release --repo "$R"
gh secret set ASC_ISSUER_ID --env release --repo "$R"
gh secret set ASC_KEY_P8 --env release --repo "$R" < PATH/TO/AuthKey_KEYID.p8
gh variable set APPLE_TEAM_ID --repo "$R" --body YOUR_TEAM_ID
```

`gh secret set` without a value prompts for it.

## 4. Upload

1. Trigger the upload: `gh workflow run CI --repo itrap-com/local-gallery-ios -f upload=true`, or use the Run workflow button.
2. Approve the `release` deployment on the run page.
3. The job runs these steps:
   1. archives the app, unsigned
   2. scans the release binary for networking code and attaches the scan to the run
   3. signs it with the cloud-managed certificate and uploads the build
4. Wait for Apple's processing. App Store Connect sends an email when the build is ready.
5. In App Store Connect → TestFlight, create an **internal** testing group and add yourself.
6. Install the build from the TestFlight app on your iPhone.

TestFlight builds share crash reports with the developer automatically. That runs through Apple, not
through Gallery, and is the only data path a TestFlight build has.
