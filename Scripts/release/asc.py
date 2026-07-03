#!/usr/bin/env python3
"""Minimal App Store Connect API client using the user's stored key.
Usage: asc.py METHOD /v1/path ['{json body}']"""
import jwt, time, os, sys, json, urllib.request, urllib.error

HOME = os.path.expanduser('~')
CFG = json.load(open(f'{HOME}/.appstoreconnect/api_key.json'))
KEY_ID, ISSUER = CFG['key_id'], CFG['issuer_id']
P8 = open(f'{HOME}/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8').read()

def token():
    now = int(time.time())
    return jwt.encode({'iss': ISSUER, 'iat': now, 'exp': now + 1200, 'aud': 'appstoreconnect-v1'},
                      P8, algorithm='ES256', headers={'kid': KEY_ID, 'typ': 'JWT'})

def call(method, path, body=None):
    url = 'https://api.appstoreconnect.apple.com' + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
        headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, (json.load(r) if r.length != 0 else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {'raw': raw.decode(errors='replace')}

if __name__ == '__main__':
    method, path = sys.argv[1], sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    st, resp = call(method, path, body)
    print("HTTP", st)
    print(json.dumps(resp, indent=1))
