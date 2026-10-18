#!/usr/bin/env python3
"""Print the UDID of an available iPhone simulator on the newest installed iOS runtime."""
import json
import subprocess
import sys


def runtime_version(identifier):
    tail = identifier.rsplit(".", 1)[-1]  # e.g. iOS-26-0
    if not tail.startswith("iOS-"):
        return None
    try:
        return tuple(int(part) for part in tail[4:].split("-"))
    except ValueError:
        return None


def main():
    listing = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        capture_output=True, text=True, check=True,
    ).stdout
    candidates = []
    for runtime, devices in json.loads(listing)["devices"].items():
        version = runtime_version(runtime)
        if version is None:
            continue
        for device in devices:
            if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
                candidates.append((version, device["name"], device["udid"]))
    if not candidates:
        print("no available iPhone simulator", file=sys.stderr)
        return 1
    candidates.sort()
    version, name, udid = candidates[-1]
    print(f"using {name} on iOS {'.'.join(map(str, version))}", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
