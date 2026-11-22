"""Read-only Play status: tracks and releases for each package."""
import json, sys, time, urllib.request, urllib.error
import jwt
sa = json.load(open(sys.argv[1]))
now = int(time.time())
a = jwt.encode({"iss": sa["client_email"], "scope": "https://www.googleapis.com/auth/androidpublisher",
                "aud": "https://oauth2.googleapis.com/token", "iat": now, "exp": now + 3000}, sa["private_key"], algorithm="RS256")
tok = json.load(urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token",
      data=("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" + a).encode())))["access_token"]
B = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"
def call(m, u):
    r = urllib.request.Request(u, method=m, headers={"Authorization": "Bearer " + tok})
    try:
        raw = urllib.request.urlopen(r).read()
        return 200, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read() or b"{}")
for pkg in sys.argv[2:]:
    print("==", pkg)
    s, e = call("POST", B + pkg + "/edits")
    if s != 200:
        print("  ERROR", s, e.get("error", {}).get("message")); continue
    s, t = call("GET", B + pkg + "/edits/" + e["id"] + "/tracks")
    for tr in t.get("tracks", []):
        for r in tr.get("releases", []):
            print("  %-10s %-12s versionCodes=%s name=%s" % (tr["track"], r.get("status"), r.get("versionCodes"), r.get("name")))
    if not t.get("tracks"): print("  no tracks", s, t)
    for tn in sorted({tr["track"] for tr in t.get("tracks", [])} | {"alpha"}):
        s2, te = call("GET", B + pkg + "/edits/" + e["id"] + "/testers/" + tn)
        if s2 == 200:
            print("  testers[%s]: google groups=%d" % (tn, len(te.get("googleGroups", []))))
    call("DELETE", B + pkg + "/edits/" + e["id"])
