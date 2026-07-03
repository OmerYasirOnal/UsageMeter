import asc, sys, json, os

# Attach a build to the 0.2.0 version and prepare the App Review submission.
# Final submit is gated behind CONFIRM=1 so nothing is sent to Apple by accident.
#   python3 submit.py <build_id>            -> attach + prepare (no submit)
#   CONFIRM=1 python3 submit.py <build_id>  -> attach + prepare + SUBMIT FOR REVIEW

VERSION = "23ab8b3b-60f9-4836-8bad-7a1ea2b2e051"
APP = "6786227263"
BUILD_ID = sys.argv[1] if len(sys.argv) > 1 else None

def show(label, st, r):
    err = r.get("errors") if isinstance(r, dict) else None
    ok = not err
    print(label, st, ("OK" if ok else json.dumps(err[0].get("detail", err[0]))[:240]))
    return ok

if not BUILD_ID:
    print("usage: [CONFIRM=1] python3 submit.py <build_id>"); sys.exit(1)

# 1. attach the build to the version
st, r = asc.call("PATCH", f"/v1/appStoreVersions/{VERSION}/relationships/build",
                 {"data": {"type": "builds", "id": BUILD_ID}})
show("attach build   :", st, r)

# 2. find an open review submission for macOS, else create one
st, r = asc.call("GET", f"/v1/apps/{APP}/reviewSubmissions?filter[platform]=MAC_OS")
subs = r.get("data", []) if isinstance(r, dict) else []
open_states = ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES", "COMPLETING")
sub_id = next((s["id"] for s in subs if s["attributes"].get("state") in open_states), None)
if sub_id:
    print("reviewSubmission: reuse", sub_id)
else:
    st, r = asc.call("POST", "/v1/reviewSubmissions",
                     {"data": {"type": "reviewSubmissions", "attributes": {"platform": "MAC_OS"},
                               "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
    if not show("reviewSubmission:", st, r): sys.exit(1)
    sub_id = r["data"]["id"]

# 3. add the version as a submission item (ok if it already exists)
st, r = asc.call("POST", "/v1/reviewSubmissionItems",
                 {"data": {"type": "reviewSubmissionItems",
                           "relationships": {
                               "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                               "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION}}}}})
show("add version item:", st, r)

# 4. final submit — only with CONFIRM=1
if os.environ.get("CONFIRM") == "1":
    st, r = asc.call("PATCH", f"/v1/reviewSubmissions/{sub_id}",
                     {"data": {"type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}})
    show("SUBMIT REVIEW  :", st, r)
else:
    print(f"PREPARED reviewSubmission {sub_id} — re-run with CONFIRM=1 to submit for review.")
