import asc, hashlib, json, urllib.request, sys

VLOC = "aad4ce77-1b02-4fc6-acb5-d07739eecf59"
FILE = sys.argv[1] if len(sys.argv) > 1 else "appstore_screenshot_1.png"
data = open(FILE, "rb").read()
size = len(data)
print("file:", FILE, "size:", size)

# 1. find or create APP_DESKTOP screenshot set
st, r = asc.call("GET", f"/v1/appStoreVersionLocalizations/{VLOC}/appScreenshotSets")
setid = next((s["id"] for s in r.get("data", []) if s["attributes"].get("screenshotDisplayType") == "APP_DESKTOP"), None)
if not setid:
    st, r = asc.call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": "APP_DESKTOP"},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": VLOC}}}}})
    if "errors" in r: print("set create FAILED:", r["errors"]); sys.exit(1)
    setid = r["data"]["id"]
print("screenshot set:", setid)

# 2. reserve the screenshot
st, r = asc.call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
    "attributes": {"fileName": FILE, "fileSize": size},
    "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": setid}}}}})
if "errors" in r: print("reserve FAILED:", r["errors"]); sys.exit(1)
shotid = r["data"]["id"]
ops = r["data"]["attributes"]["uploadOperations"]
print("reserved:", shotid, "| upload ops:", len(ops))

# 3. upload the bytes per operation
for op in ops:
    chunk = data[op["offset"]:op["offset"] + op["length"]]
    req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
    for h in op.get("requestHeaders", []):
        req.add_header(h["name"], h["value"])
    with urllib.request.urlopen(req) as resp:
        pass
print("uploaded", size, "bytes")

# 4. commit
md5 = hashlib.md5(data).hexdigest()
st, r = asc.call("PATCH", f"/v1/appScreenshots/{shotid}", {"data": {"type": "appScreenshots", "id": shotid,
    "attributes": {"uploaded": True, "sourceFileChecksum": md5}}})
print("commit:", st, r.get("errors") if isinstance(r, dict) and r.get("errors") else "OK ✓")
