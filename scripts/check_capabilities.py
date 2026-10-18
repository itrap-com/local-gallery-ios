#!/usr/bin/env python3
"""G-08 capability allowlist: the iOS counterpart of the Android APK permission allowlist.

Checks Config/Info.plist keys, Info.plist keys generated from build settings, and entitlements.
Anything not listed here fails until it is reviewed and added on purpose.
"""
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INFO_PLIST = ROOT / "Config" / "Info.plist"
PBXPROJ = ROOT / "LocalGallery.xcodeproj" / "project.pbxproj"

ALLOWED_INFO_KEYS = {
    "CFBundleDisplayName",
    "ITSAppUsesNonExemptEncryption",
    "NSPhotoLibraryUsageDescription",
    "PHPhotoLibraryPreventAutomaticLimitedAccessAlert",
}
ALLOWED_GENERATED_KEYS = {
    "LSApplicationCategoryType",
    "UIApplicationSceneManifest_Generation",
    "UIApplicationSupportsIndirectInputEvents",
    "UILaunchScreen_Generation",
    "UISupportedInterfaceOrientations_iPhone",
}


def main():
    problems = []
    if not INFO_PLIST.exists() or not PBXPROJ.exists():
        print("capabilities: Info.plist or project file missing (fail closed)")
        return 1
    info = plistlib.loads(INFO_PLIST.read_bytes())
    for key in sorted(set(info) - ALLOWED_INFO_KEYS):
        problems.append(f"Config/Info.plist: unreviewed key {key}")
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        problems.append("Config/Info.plist: ITSAppUsesNonExemptEncryption must stay false until the Vault ships")
    if info.get("PHPhotoLibraryPreventAutomaticLimitedAccessAlert") is not True:
        problems.append("Config/Info.plist: the automatic limited-access alert must stay suppressed (no nagging)")

    project = PBXPROJ.read_text()
    for key in sorted(set(re.findall(r"INFOPLIST_KEY_([A-Za-z0-9_]+)", project)) - ALLOWED_GENERATED_KEYS):
        problems.append(f"project.pbxproj: unreviewed generated Info.plist key {key}")
    if "CODE_SIGN_ENTITLEMENTS" in project:
        problems.append("project.pbxproj: entitlements are not allowed yet (no iCloud, push, networking or app groups)")
    for path in ROOT.rglob("*.entitlements"):
        problems.append(f"{path.relative_to(ROOT)}: entitlements file present")

    for p in problems:
        print(p)
    print(f"capabilities: {'FAIL' if problems else 'ok'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
