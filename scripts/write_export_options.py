#!/usr/bin/env python3
"""Write the ExportOptions.plist that signs the archive for App Store Connect and uploads it.

Signing is automatic: the export runs with -allowProvisioningUpdates and the App Store Connect
API key, so Apple's cloud-managed distribution certificate signs it. No certificate or profile
is stored anywhere.

    python3 scripts/write_export_options.py TEAM_ID OUT.plist
"""
import plistlib
import sys


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    team_id, out = sys.argv[1:]
    options = {
        "method": "app-store-connect",
        "destination": "upload",
        "teamID": team_id,
        "signingStyle": "automatic",
        "manageAppVersionAndBuildNumber": False,
        "uploadSymbols": True,
    }
    with open(out, "wb") as handle:
        plistlib.dump(options, handle)
    return 0


if __name__ == "__main__":
    sys.exit(main())
