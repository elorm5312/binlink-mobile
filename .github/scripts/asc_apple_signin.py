"""Make sure Sign in with Apple is enabled on the App IDs, via the App Store Connect API.

Uses the same key as the rest of the iOS workflow (APP_STORE_CONNECT_* env vars).
When the capability is newly switched on, Apple invalidates the existing App Store
profiles, so those are deleted and `fetch-signing-files --create` makes fresh ones.

    python3 asc_apple_signin.py com.binlink.eco com.binlink.collector
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
key = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].replace("\\n", "\n")
now = int(time.time())
token = jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 1000,
                    "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                   headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"})


def call(method, path, body=None):
    req = urllib.request.Request(path if path.startswith("http") else API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, json.loads(raw) if raw else {}


failed = False
for identifier in sys.argv[1:]:
    s, b = call("GET", "/bundleIds?filter[identifier]=%s&limit=20" % identifier)
    match = [d for d in b.get("data", []) if d["attributes"]["identifier"] == identifier]
    if s != 200 or not match:
        print("::error::App ID %s not found (%s)" % (identifier, s))
        failed = True
        continue
    rid = match[0]["id"]
    s, b = call("GET", "/bundleIds/%s/bundleIdCapabilities" % rid)
    have = {d["attributes"]["capabilityType"] for d in b.get("data", [])}
    if "APPLE_ID_AUTH" in have:
        print("%s: Sign in with Apple already on" % identifier)
        newly = False
    else:
        s, b = call("POST", "/bundleIdCapabilities", {"data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": "APPLE_ID_AUTH", "settings": [
                {"key": "APPLE_ID_AUTH_APP_CONSENT", "options": [{"key": "PRIMARY_APP_CONSENT"}]}]},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": rid}}}}})
        if s not in (200, 201):
            print("::error::%s: could not enable Sign in with Apple: %s %s" % (identifier, s, json.dumps(b)[:400]))
            failed = True
            continue
        print("%s: Sign in with Apple switched on" % identifier)
        newly = True
    # Remove App Store profiles that predate the capability or are no longer valid.
    s, b = call("GET", "/bundleIds/%s/profiles?limit=50" % rid)
    for p in b.get("data", []):
        a = p["attributes"]
        if a.get("profileType") == "IOS_APP_STORE" and (newly or a.get("profileState") != "ACTIVE"):
            ds, _ = call("DELETE", "/profiles/%s" % p["id"])
            print("  removed old profile %s (%s) -> %s" % (a.get("name"), a.get("profileState"), ds))

sys.exit(1 if failed else 0)
