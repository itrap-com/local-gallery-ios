#!/usr/bin/env python3
"""G-04 source lint: patterns that would break the privacy promise or the honest-wording rules.

Fails closed: no Swift sources found is a failure. Stdlib only; runs on the Linux runner.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = ["LocalGallery", "LocalGalleryTests", "Core/Sources", "Core/Tests"]

RULES = [
    (r"\b(print|debugPrint|NSLog)\(", "no console logging: media metadata must never reach logs"),
    (r"\bos_log\(|\bLogger\(", "logging needs a privacy review before it is added"),
    (r"isNetworkAccessAllowed\s*=\s*true", "downloading iCloud originals is an owner decision (D-07)"),
    (r"\b(URLSession|URLRequest|NWConnection|NWListener|WKWebView|SFSafariViewController|MKMapView|CLGeocoder)\b",
     "no networking: Gallery has no network code of its own"),
    (r"includeHiddenAssets\s*=\s*true", "system-hidden assets are read only by the Hidden feature"),
    (r"\bUserDefaults\b|@AppStorage", "UserDefaults is a required-reason API; declare it in PrivacyInfo.xcprivacy first"),
    (r"(?i)\b(secure|encrypted)\s+(hidden|album)\b", "Hidden is a view filter, never described as secure or encrypted"),
]


def main():
    files = [p for d in SOURCE_DIRS for p in (ROOT / d).rglob("*.swift")]
    if not files:
        print("lint: no Swift sources found (fail closed)")
        return 1
    failures = 0
    for path in sorted(files):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for pattern, reason in RULES:
                if re.search(pattern, line):
                    print(f"{path.relative_to(ROOT)}:{number}: {reason}")
                    failures += 1
    print(f"lint: {len(files)} files, {failures} findings")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
