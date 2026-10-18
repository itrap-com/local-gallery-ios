#!/usr/bin/env python3
"""G-07 privacy manifest: no tracking, no tracking domains, no collected data, and only
reviewed required-reason API declarations. Fails closed when the manifest is missing."""
import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "LocalGallery" / "PrivacyInfo.xcprivacy"

# Required-reason API categories the app may declare, each with its reviewed reason codes.
ALLOWED_API_TYPES: dict[str, set[str]] = {}


def main():
    if not MANIFEST.exists():
        print(f"privacy manifest missing: {MANIFEST.relative_to(ROOT)}")
        return 1
    manifest = plistlib.loads(MANIFEST.read_bytes())
    problems = []
    if manifest.get("NSPrivacyTracking") is not False:
        problems.append("NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        problems.append("NSPrivacyTrackingDomains must be an empty list")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        problems.append("NSPrivacyCollectedDataTypes must be empty: Gallery collects no data")
    api_types = manifest.get("NSPrivacyAccessedAPITypes")
    if not isinstance(api_types, list):
        problems.append("NSPrivacyAccessedAPITypes must be a list")
    else:
        for entry in api_types:
            kind = entry.get("NSPrivacyAccessedAPIType")
            reasons = set(entry.get("NSPrivacyAccessedAPITypeReasons", []))
            allowed = ALLOWED_API_TYPES.get(kind)
            if allowed is None:
                problems.append(f"unreviewed required-reason API category: {kind}")
            elif not reasons or not reasons <= allowed:
                problems.append(f"unreviewed reasons for {kind}: {sorted(reasons - allowed)}")
    for p in problems:
        print(f"{MANIFEST.relative_to(ROOT)}: {p}")
    print(f"privacy manifest: {'FAIL' if problems else 'ok'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
