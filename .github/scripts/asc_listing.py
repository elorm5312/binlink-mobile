"""Fill in the App Store page for each app from .github/appstore/listing.json.

Idempotent: safe to run again. Each step prints OK / ERROR and the run continues,
so one problem does not hide the others. Never submits for review.

    python3 asc_listing.py [--attach-build]

Optional env: DEMO_ECO_USER / DEMO_ECO_PASS, DEMO_COLLECTOR_USER / DEMO_COLLECTOR_PASS
(reviewer sign-in; leave unset until the accounts exist).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
key = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].replace("\\n", "\n")
now = int(time.time())
token = jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 1100,
                    "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                   headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"})
L = json.load(open(os.path.join(os.path.dirname(__file__), "..", "appstore", "listing.json")))
ATTACH = "--attach-build" in sys.argv
problems = []


def call(method, path, body=None):
    url = path if path.startswith("http") else API + (path if path.startswith("/v") else "/v1" + path)
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw) if raw else {}
        except ValueError:
            return e.code, {"raw": raw[:300].decode("utf-8", "replace")}


def report(label, s, b):
    if s in (200, 201, 204):
        print("  OK     %s" % label)
        return True
    errs = b.get("errors") or [b]
    msg = "; ".join("%s %s" % (e.get("code", ""), e.get("detail") or e.get("title") or e) for e in errs)[:500]
    print("  ERROR  %s (%s): %s" % (label, s, msg))
    problems.append("%s: %s" % (label, msg))
    return False


def patch(kind, rid, attrs, label, rels=None):
    data = {"type": kind, "id": rid}
    if attrs:
        data["attributes"] = attrs
    if rels:
        data["relationships"] = rels
    return report(label, *call("PATCH", "/%s/%s" % (kind, rid), {"data": data}))


for bundle, cfg in L["apps"].items():
    print("=" * 64)
    s, b = call("GET", "/apps?filter%%5BbundleId%%5D=%s" % bundle)
    if s != 200 or not b.get("data"):
        report("find app %s" % bundle, s, b)
        continue
    app = b["data"][0]
    aid = app["id"]
    print("%s (%s)" % (cfg["name"], aid))

    patch("apps", aid, {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}, "content rights")

    # ---- App info: category, name, subtitle, privacy URL, age rating ----
    s, b = call("GET", "/apps/%s/appInfos" % aid)
    infos = [i for i in b.get("data", []) if i["attributes"].get("appStoreState", i["attributes"].get("state"))
             not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")] or b.get("data", [])
    if not infos:
        report("app info", s, b)
        continue
    info = infos[0]["id"]
    patch("appInfos", info, None, "category %s" % cfg["category"],
          {"primaryCategory": {"data": {"type": "appCategories", "id": cfg["category"]}}})
    s, b = call("GET", "/appInfos/%s/appInfoLocalizations" % info)
    for loc in b.get("data", []):
        patch("appInfoLocalizations", loc["id"], {"name": cfg["name"], "subtitle": cfg["subtitle"],
                                                   "privacyPolicyUrl": L["privacy_url"]},
              "name/subtitle/privacy URL (%s)" % loc["attributes"]["locale"])

    s, b = call("GET", "/appInfos/%s/ageRatingDeclaration" % info)
    if s == 200 and b.get("data"):
        rid = b["data"]["id"]
        none = {k: "NONE" for k in (
            "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
            "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
            "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy",
            "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic")}
        none.update({"gambling": False, "unrestrictedWebAccess": False})
        # Newer questions (2025+). Chat with the collector/household is user-to-user messaging.
        none.update({"messagingAndChat": True, "userGeneratedContent": False, "advertising": False,
                     "healthOrWellnessTopics": False, "parentalControls": False, "ageAssurance": False,
                     "lootBox": False, "socialMedia": False, "gunsOrOtherWeapons": "NONE"})
        for _ in range(4):
            s2, b2 = call("PATCH", "/ageRatingDeclarations/%s" % rid,
                          {"data": {"type": "ageRatingDeclarations", "id": rid, "attributes": none}})
            if s2 == 200:
                print("  OK     age rating (%d questions)" % len(none))
                break
            import re
            missing = set(re.findall(r"attribute '(\w+)' with this request", json.dumps(b2)))
            unknown = set(re.findall(r"'(\w+)' is not (?:a valid|allowed|an allowed)", json.dumps(b2)))
            if not missing and not unknown:
                report("age rating", s2, b2)
                break
            print("  retry  age rating: adding %s, dropping %s" % (sorted(missing - set(none)), sorted(unknown)))
            for k in missing - set(none):
                none[k] = False
            for k in unknown:
                none.pop(k, None)
        else:
            report("age rating", s2, b2)
    else:
        report("age rating", s, b)

    # ---- Price: free ----
    s, b = call("GET", "/apps/%s/appPriceSchedule" % aid)
    if s == 200 and b.get("data"):
        print("  OK     price schedule already set")
    else:
        s, b = call("GET", "/apps/%s/appPricePoints?filter%%5Bterritory%%5D=USA&limit=200" % aid)
        free = [p for p in b.get("data", []) if float(p["attributes"].get("customerPrice") or 1) == 0]
        if not free:
            report("find free price point", s, b)
        else:
            report("price: free", *call("POST", "/appPriceSchedules", {
                "data": {"type": "appPriceSchedules", "relationships": {
                    "app": {"data": {"type": "apps", "id": aid}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": [{"type": "appPrices", "id": "${p0}"}]}}},
                "included": [{"type": "appPrices", "id": "${p0}", "attributes": {"startDate": None},
                              "relationships": {"appPricePoint": {"data": {"type": "appPricePoints",
                                                                            "id": free[0]["id"]}}}}]}))

    # ---- App Store version ----
    s, b = call("GET", "/apps/%s/appStoreVersions?filter%%5Bplatform%%5D=IOS&limit=10" % aid)
    editable = [v for v in b.get("data", []) if v["attributes"].get("appStoreState") in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
    if not editable:
        report("find editable App Store version", s, b)
        continue
    ver = editable[0]["id"]
    patch("appStoreVersions", ver, {"versionString": L["version"], "copyright": L["copyright"]},
          "version %s + copyright" % L["version"])

    s, b = call("GET", "/appStoreVersions/%s/appStoreVersionLocalizations" % ver)
    for loc in b.get("data", []):
        patch("appStoreVersionLocalizations", loc["id"], {
            "description": cfg["description"], "keywords": cfg["keywords"], "promotionalText": cfg["promo"],
            "supportUrl": L["support_url"], "marketingUrl": L["support_url"]},
              "description/keywords/URLs (%s)" % loc["attributes"]["locale"])
        s2, b2 = call("GET", "/appStoreVersionLocalizations/%s/appScreenshotSets" % loc["id"])
        sets = [x["attributes"]["screenshotDisplayType"] for x in b2.get("data", [])]
        print("  info   screenshot sets: %s" % (sets or "none yet"))

    # ---- Review information ----
    short = "ECO" if bundle.endswith(".eco") else "COLLECTOR"
    user, pw = os.environ.get("DEMO_%s_USER" % short), os.environ.get("DEMO_%s_PASS" % short)
    c = L["contact"]
    attrs = {"contactFirstName": c["first"], "contactLastName": c["last"], "contactPhone": c["phone"],
             "contactEmail": c["email"], "notes": cfg["review_notes"]}
    if user and pw:
        attrs.update({"demoAccountRequired": True, "demoAccountName": user, "demoAccountPassword": pw})
    s, b = call("GET", "/appStoreVersions/%s/appStoreReviewDetail" % ver)
    if s == 200 and b.get("data"):
        patch("appStoreReviewDetails", b["data"]["id"], attrs, "review contact + notes")
    else:
        report("review contact + notes", *call("POST", "/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver}}}}}))
    print("  info   demo account: %s" % ("set" if user and pw else "NOT SET YET"))

    # ---- Build ----
    if ATTACH:
        s, b = call("GET", "/builds?filter%%5Bapp%%5D=%s&filter%%5BpreReleaseVersion.version%%5D=%s"
                           "&filter%%5BprocessingState%%5D=VALID&sort=-uploadedDate&limit=1" % (aid, L["version"]))
        if b.get("data"):
            bid = b["data"][0]["id"]
            report("attach build %s (%s)" % (L["version"], b["data"][0]["attributes"]["version"]),
                   *call("PATCH", "/appStoreVersions/%s/relationships/build" % ver,
                         {"data": {"type": "builds", "id": bid}}))
        else:
            report("attach build", s, {"errors": [{"detail": "no processed %s build yet" % L["version"]}]})

print("=" * 64)
print("%d problem(s)" % len(problems))
for p in problems:
    print(" -", p)
