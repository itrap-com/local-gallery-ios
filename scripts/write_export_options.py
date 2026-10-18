#!/usr/bin/env python3
"""Write the ExportOptions.plist that signs the archive for App Store Connect and uploads it.

    python3 scripts/write_export_options.py TEAM_ID PROFILE_NAME OUT.plist
"""
import plistlib
import sys

BUNDLE_ID = "local-gallery.ios"


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    team_id, profile_name, out = sys.argv[1:]
    options = {
        "method": "app-store-connect",
        "destination": "upload",
        "teamID": team_id,
        "signingStyle": "manual",
        "signingCertificate": "Apple Distribution",
        "provisioningProfiles": {BUNDLE_ID: profile_name},
        "manageAppVersionAndBuildNumber": False,
        "uploadSymbols": True,
    }
    with open(out, "wb") as handle:
        plistlib.dump(options, handle)
    return 0


if __name__ == "__main__":
    sys.exit(main())
