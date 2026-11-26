#!/usr/bin/env python3
"""Attach an uploaded build to Hijry's beta groups and submit it for review."""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def encode(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token():
    now = int(time.time())
    header = encode(json.dumps({"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}).encode())
    payload = encode(json.dumps({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    message = header + "." + payload
    der = subprocess.check_output(["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]], input=message.encode())
    if der[0] != 0x30 or der[2] != 0x02:
        raise ValueError("Unexpected ECDSA signature encoding")
    r_length = der[3]
    r = int.from_bytes(der[4:4 + r_length], "big")
    offset = 4 + r_length
    if der[offset] != 0x02:
        raise ValueError("Unexpected ECDSA signature encoding")
    s_length = der[offset + 1]
    s = int.from_bytes(der[offset + 2:offset + 2 + s_length], "big")
    return message + "." + encode(r.to_bytes(32, "big") + s.to_bytes(32, "big"))


def request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, data=data,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            content = response.read()
            return json.loads(content) if content else {}
    except urllib.error.HTTPError as error:
        details = json.loads(error.read())
        for item in details.get("errors", []):
            print("Apple API", error.code, item.get("code"), item.get("detail"), file=sys.stderr)
        raise SystemExit(1)


def main():
    app_id, build_number = sys.argv[1:]
    query = urllib.parse.urlencode({"filter[app]": app_id, "filter[version]": build_number})
    build = None
    for attempt in range(21):
        builds = request("GET", "/v1/builds?" + query)["data"]
        if builds:
            build = builds[0]
            state = build["attributes"]["processingState"]
            print("Build processing state", state, flush=True)
            if state == "VALID":
                break
            if state in {"INVALID", "FAILED"}:
                raise SystemExit("Apple could not process the build")
        if attempt == 20:
            raise SystemExit("Apple is still processing the uploaded build. Retry beta setup after processing completes.")
        time.sleep(30)
    build_id = build["id"]
    request("PATCH", "/v1/builds/" + build_id, {"data": {"type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": False}}})
    instructions = "تحديث 5.56 لأجهزة iPhone وiPad. يرجى تجربة الثيمات الخمسة والسبينر وزر تاريخ اليوم وبطاقات العمر والفرق بين تاريخين، ومهام الرواتب والصيام والمواعيد والطقس والويدجت."
    for localization in request("GET", f"/v1/builds/{build_id}/betaBuildLocalizations")["data"]:
        request("PATCH", "/v1/betaBuildLocalizations/" + localization["id"], {"data": {"type": "betaBuildLocalizations", "id": localization["id"], "attributes": {"whatsNew": instructions}}})
    groups = request("GET", f"/v1/apps/{app_id}/betaGroups")["data"]
    for group in groups:
        if group["attributes"]["name"] not in {"Internal Testing", "Hijry Public Beta"}:
            continue
        group_id = group["id"]
        request("POST", f"/v1/betaGroups/{group_id}/relationships/builds", {"data": [{"type": "builds", "id": build_id}]})
        older = request("GET", f"/v1/betaGroups/{group_id}/builds")["data"]
        old_ids = [{"type": "builds", "id": item["id"]} for item in older if item["id"] != build_id]
        if old_ids:
            request("DELETE", f"/v1/betaGroups/{group_id}/relationships/builds", {"data": old_ids})
        print("Updated beta group", group["attributes"]["name"], flush=True)
        if group["attributes"].get("publicLink"):
            print("Public TestFlight link", group["attributes"]["publicLink"], flush=True)
    detail = request("GET", f"/v1/builds/{build_id}/buildBetaDetail")["data"]["attributes"]
    state = detail["externalBuildState"]
    if state == "READY_FOR_BETA_SUBMISSION":
        submission = request("POST", "/v1/betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
        print("Beta review state", submission["data"]["attributes"]["betaReviewState"])
    else:
        print("External beta state", state)
    print("Configured TestFlight build", build_number)


if __name__ == "__main__":
    main()
