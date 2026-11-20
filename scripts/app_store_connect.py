"""Small App Store Connect API client authenticated with an API key (.p8)."""

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API_ROOT = "https://api.appstoreconnect.apple.com"
TOKEN_LIFETIME_SECONDS = 15 * 60


class AppStoreConnectError(RuntimeError):
    pass


class AppStoreConnect:
    def __init__(self, key_id, issuer_id, private_key):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.private_key = private_key

    @classmethod
    def from_environment(cls):
        return cls(
            os.environ["ASC_KEY_ID"],
            os.environ["ASC_ISSUER_ID"],
            os.environ["ASC_PRIVATE_KEY"],
        )

    def _token(self):
        now = int(time.time())
        return jwt.encode(
            {"iss": self.issuer_id, "iat": now, "exp": now + TOKEN_LIFETIME_SECONDS, "aud": "appstoreconnect-v1"},
            self.private_key,
            algorithm="ES256",
            headers={"kid": self.key_id, "typ": "JWT"},
        )

    def request(self, method, path, body=None, params=None):
        url = API_ROOT + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", f"Bearer {self._token()}")
        request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request) as response:
                payload = response.read()
        except urllib.error.HTTPError as error:
            raise AppStoreConnectError(f"{method} {path} failed with {error.code}: {error.read().decode()}") from error
        return json.loads(payload) if payload else {}

    def get(self, path, **params):
        return self.request("GET", path, params=params)

    def post(self, path, body):
        return self.request("POST", path, body=body)

    def patch(self, path, body):
        return self.request("PATCH", path, body=body)

    def app_id_for_bundle(self, bundle_id):
        apps = self.get("/v1/apps", **{"filter[bundleId]": bundle_id})["data"]
        if not apps:
            raise AppStoreConnectError(f"No App Store Connect app has bundle ID {bundle_id}")
        return apps[0]["id"]
