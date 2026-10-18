#!/usr/bin/env python3
"""G-06 dependency allowlist. iOS has no network permission to fall back on, so every third-party
package must be named here after a review; anything else fails.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PBXPROJ = ROOT / "LocalGallery.xcodeproj" / "project.pbxproj"
CORE_MANIFEST = ROOT / "Core" / "Package.swift"

# Reviewed package identities (lowercase). Empty: the app ships no third-party code.
ALLOWED_PACKAGES: set[str] = set()


def main():
    problems = []
    if not PBXPROJ.exists() or not CORE_MANIFEST.exists():
        print("dependencies: project file or Core/Package.swift missing (fail closed)")
        return 1
    if "XCRemoteSwiftPackageReference" in PBXPROJ.read_text():
        problems.append("project.pbxproj: remote Swift package reference (needs review and an allowlist entry)")
    if ".package(" in CORE_MANIFEST.read_text():
        problems.append("Core/Package.swift: package dependency declared (needs review and an allowlist entry)")
    for resolved in ROOT.rglob("Package.resolved"):
        pins = json.loads(resolved.read_text()).get("pins", [])
        for pin in pins:
            identity = pin.get("identity", "").lower()
            if identity not in ALLOWED_PACKAGES:
                problems.append(f"{resolved.relative_to(ROOT)}: unreviewed package {identity}")
    for pattern in ("Podfile", "Cartfile", "*.xcframework", "*.framework"):
        for path in ROOT.rglob(pattern):
            if ".git" not in path.parts:
                problems.append(f"{path.relative_to(ROOT)}: vendored or third-party package manager artifact")
    for p in problems:
        print(p)
    print(f"dependencies: {'FAIL' if problems else 'ok'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
