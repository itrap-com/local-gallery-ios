# CLAUDE.md — Local Gallery for iOS

The iOS sibling of the Android app in `../local-gallery`. The design dossier at
`../local-gallery-ios-dossier/` holds the reasoning. Read its `00-README.md` and
`15-owner-decisions.md` before changing direction.

## Absolute rules
- **No networking code.** No network frameworks or calls; `isNetworkAccessAllowed` stays false.
  The source lint and `scripts/scan_network_symbols.py` enforce this. iOS has no network
  permission to fall back on.
- **No telemetry or accounts.** No analytics, crash-reporting, ads or account SDKs. No third-party
  package without a written review and an entry in `scripts/check_dependencies.py`.
- **No sensitive logs.** Never log or expose filenames, places, capture times, album names,
  identifiers or search text. Accessibility labels stay generic ("Photo", "Video, N seconds").
- **The library is read-only until a slice says otherwise.** Any future write goes through PhotoKit
  change requests with the system confirmation.
- **Limited access is a first-class state.** An empty fetch never claims "no photos". Never nag:
  the automatic limited-access alert stays suppressed.
- **Honest wording.** Hidden is a view filter, never "secure" or "encrypted". Only the Vault, when it
  ships, is encryption.
- **Info.plist, entitlements and the privacy manifest are allowlisted.**
  `scripts/check_capabilities.py` and `check_privacy_manifest.py` must pass. Change them only with
  the owner's approval.

## Workflow
- There is no Mac. Build and test through GitHub Actions; read results with
  `gh run view --log-failed` and `gh run download`. Put platform-free logic in `Core/`, which is
  tested on Linux.
- **The project file:** change targets or settings in `scripts/gen_xcodeproj.py`, then regenerate.
  Never hand-edit `project.pbxproj`; CI fails on drift.
- **Commits:** never run git commit. The owner signs every commit: stage the files and hand over
  the command.
- **Signing:** signing material and App Store Connect keys exist only as `release` environment
  secrets. Never generate, print or commit them.
