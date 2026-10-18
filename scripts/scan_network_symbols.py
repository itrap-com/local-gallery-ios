#!/usr/bin/env python3
"""G-05 networking-symbol scan of a built .app (macOS runner; needs otool and nm from Xcode).

iOS has no network permission to withhold, so this scan is how each build shows it carries no
networking code of its own: no networking frameworks linked, no networking classes or calls.
Fails closed when a binary cannot be read or yields no imported symbols.

    python3 scripts/scan_network_symbols.py path/to/LocalGallery.app
"""
import plistlib
import re
import subprocess
import sys
from pathlib import Path

DENIED_FRAMEWORKS = {
    "CFNetwork", "Network", "WebKit", "SafariServices", "MapKit", "StoreKit", "CloudKit",
    "MultipeerConnectivity", "NetworkExtension", "MessageUI", "AuthenticationServices",
}
DENIED_SYMBOLS = [
    r"URLSession", r"NSURLConnection", r"NSURLDownload", r"^_nw_", r"\$s7Network", r"CFStream",
    r"CFSocket", r"CFHost", r"^_socket$", r"^_connect$", r"^_getaddrinfo$", r"^_gethostbyname",
    r"WKWebView", r"SFSafariViewController", r"MKMapView", r"CLGeocoder",
]


def machos(app):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    yield app / info["CFBundleExecutable"]
    for extra in sorted(app.glob("Frameworks/*.framework")) + sorted(app.glob("PlugIns/*.appex")):
        extra_info = plistlib.loads((extra / "Info.plist").read_bytes())
        yield extra / extra_info["CFBundleExecutable"]
    yield from sorted(app.glob("Frameworks/*.dylib"))


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    app = Path(sys.argv[1])
    problems = []
    scanned = 0
    for binary in machos(app):
        name = binary.relative_to(app)
        libs = [line.strip().split(" (")[0] for line in run("otool", "-L", str(binary)).splitlines()[1:]]
        print(f"== {name}\nlinked:")
        for lib in libs:
            print(f"  {lib}")
            stem = Path(lib).name
            if stem in DENIED_FRAMEWORKS:
                problems.append(f"{name}: links {lib}")
        symbols = [line.strip() for line in run("nm", "-u", str(binary)).splitlines() if line.strip()]
        if not symbols:
            problems.append(f"{name}: no imported symbols parsed (fail closed)")
        for symbol in symbols:
            if any(re.search(pattern, symbol) for pattern in DENIED_SYMBOLS):
                problems.append(f"{name}: references {symbol}")
        print(f"imported symbols: {len(symbols)}")
        scanned += 1
    if scanned == 0:
        problems.append("no binaries found (fail closed)")
    for p in problems:
        print(f"DENIED {p}")
    print(f"network scan: {scanned} binaries, {'FAIL' if problems else 'clean'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
