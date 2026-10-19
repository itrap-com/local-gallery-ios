#!/usr/bin/env python3
"""Read-only App Store Connect query: which app records exist, and the processing state of their builds.

Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file). Signs the ES256 token with the
openssl command line, so it is stdlib only. Prints no secrets.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der):
    # ECDSA-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER } -> fixed 32-byte r || s
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        length = der[i + 1]
        value = der[i + 2:i + 2 + length].lstrip(b"\x00")
        out += value.rjust(32, b"\x00")
        i += 2 + length
    return out


def token():
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    now = int(time.time())
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(claims).encode())}"
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
        input=signing_input.encode(), capture_output=True, check=True,
    ).stdout
    return f"{signing_input}.{b64url(der_to_raw(der))}"


def get(path, jwt):
    req = urllib.request.Request(API + path, headers={"Authorization": f"Bearer {jwt}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as err:
        return {"http_error": err.code, "body": err.read().decode()[:800]}


def main():
    jwt = token()
    apps = get("/v1/apps?limit=50&fields[apps]=name,bundleId,sku", jwt)
    if "http_error" in apps:
        print("apps query failed:", apps)
        return 1
    print("App records:")
    for app in apps.get("data", []):
        a = app["attributes"]
        print(f"  id={app['id']} bundleId={a['bundleId']} name={a['name']} sku={a['sku']}")
    for app in apps.get("data", []):
        print(f"\nBuilds for {app['attributes']['bundleId']}:")
        builds = get(f"/v1/builds?filter[app]={app['id']}&limit=20&sort=-uploadedDate"
                     "&fields[builds]=version,processingState,uploadedDate,expired,minOsVersion", jwt)
        if "http_error" in builds:
            print("  builds query failed:", builds)
        for b in builds.get("data", []):
            a = b["attributes"]
            print(f"  build {a['version']}: {a['processingState']} uploaded={a['uploadedDate']} expired={a['expired']}")
        if not builds.get("data"):
            print("  (no builds)")
        uploads = get(f"/v1/apps/{app['id']}/buildUploads?limit=20", jwt)
        if "http_error" in uploads:
            print(f"  buildUploads: HTTP {uploads['http_error']}")
        else:
            for u in uploads.get("data", []):
                print("  upload:", json.dumps(u.get("attributes", {}))[:600])
    return 0


if __name__ == "__main__":
    sys.exit(main())
