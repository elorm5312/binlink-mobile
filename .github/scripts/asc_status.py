"""Print App Store Connect status for the apps: recent builds, processing state,
export compliance, TestFlight groups/testers and App Store versions. Read-only.

    python3 asc_status.py com.binlink.eco com.binlink.collector
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


def get(path):
    req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


for bundle in sys.argv[1:]:
    print("=" * 60)
    s, b = get("/apps?filter%%5BbundleId%%5D=%s" % bundle)
    apps = b.get("data", [])
    if s != 200 or not apps:
        print("%s: no App Store Connect app record (%s) %s" % (bundle, s, json.dumps(b.get("errors", ""))[:300]))
        continue
    app = apps[0]
    print("%s  ->  %s  (id %s)" % (bundle, app["attributes"]["name"], app["id"]))

    s, b = get("/builds?filter%%5Bapp%%5D=%s&sort=-uploadedDate&limit=5&include=preReleaseVersion" % app["id"])
    pre = {i["id"]: i["attributes"].get("version") for i in b.get("included", []) if i["type"] == "preReleaseVersions"}
    print("Builds:")
    for d in b.get("data", []):
        a = d["attributes"]
        pv = (d.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}).get("id")
        print("  %s (%s)  uploaded %s  state=%s  expired=%s  encryptionAnswered=%s" % (
            pre.get(pv, "?"), a.get("version"), (a.get("uploadedDate") or "")[:16], a.get("processingState"),
            a.get("expired"), a.get("usesNonExemptEncryption")))
        s2, b2 = get("/builds/%s/buildBetaDetail" % d["id"])
        if s2 == 200:
            bd = b2["data"]["attributes"]
            print("      TestFlight internal=%s external=%s" % (bd.get("internalBuildState"), bd.get("externalBuildState")))
    if not b.get("data"):
        print("  (none yet)")

    s, b = get("/apps/%s/betaGroups" % app["id"])
    print("TestFlight groups:")
    for g in b.get("data", []):
        s2, b2 = get("/betaGroups/%s/betaTesters?limit=50" % g["id"])
        print("  %s (internal=%s): %d testers" % (g["attributes"]["name"], g["attributes"].get("isInternalGroup"),
                                                  len(b2.get("data", []))))
    if not b.get("data"):
        print("  (no groups yet)")

    s, b = get("/apps/%s/appStoreVersions?limit=5" % app["id"])
    print("App Store versions:")
    for v in b.get("data", []):
        a = v["attributes"]
        print("  %s  %s  %s" % (a.get("versionString"), a.get("platform"), a.get("appStoreState") or a.get("appVersionState")))
    if not b.get("data"):
        print("  (none)")
