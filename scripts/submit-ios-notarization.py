#!/usr/bin/env python3
"""Submit an uploaded iOS build to Apple for Notarization so AltStore PAL can distribute it."""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from app_store_connect import AppStoreConnect, AppStoreConnectError  # noqa: E402

BUNDLE_ID = "com.pablopunk.spotifin"
BUILD_POLL_SECONDS = 60
BUILD_WAIT_SECONDS = 90 * 60
EDITABLE_VERSION_STATES = "PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED,INVALID_BINARY"


def wait_for_processed_build(api, app_id, version, build_number):
    deadline = time.time() + BUILD_WAIT_SECONDS
    while time.time() < deadline:
        builds = api.get(
            "/v1/builds",
            **{"filter[app]": app_id, "filter[version]": build_number, "filter[preReleaseVersion.version]": version},
        )["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "NOT_UPLOADED_YET"
        print(f"Build {version} ({build_number}): {state}")
        if state == "VALID":
            return builds[0]["id"]
        if state in ("FAILED", "INVALID"):
            raise AppStoreConnectError(f"Build processing ended with {state}")
        time.sleep(BUILD_POLL_SECONDS)
    raise AppStoreConnectError("Timed out while App Store Connect processed the build")


def notarization_version_attributes(version):
    return {"versionString": version, "reviewType": "NOTARIZATION"}


def build_relationship(build_id):
    return {"build": {"data": {"type": "builds", "id": build_id}}}


def upsert_notarization_version(api, app_id, version, build_id):
    editable = api.get(
        f"/v1/apps/{app_id}/appStoreVersions",
        **{"filter[platform]": "IOS", "filter[appVersionState]": EDITABLE_VERSION_STATES},
    )["data"]
    if editable:
        version_id = editable[0]["id"]
        api.patch(
            f"/v1/appStoreVersions/{version_id}",
            {
                "data": {
                    "type": "appStoreVersions",
                    "id": version_id,
                    "attributes": notarization_version_attributes(version),
                    "relationships": build_relationship(build_id),
                }
            },
        )
        return version_id
    created = api.post(
        "/v1/appStoreVersions",
        {
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", **notarization_version_attributes(version)},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}, **build_relationship(build_id)},
            }
        },
    )
    return created["data"]["id"]


def set_whats_new_unless_first_version(api, version_id, notes):
    localizations = api.get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
    for localization in localizations:
        try:
            api.patch(
                f"/v1/appStoreVersionLocalizations/{localization['id']}",
                {"data": {"type": "appStoreVersionLocalizations", "id": localization["id"], "attributes": {"whatsNew": notes}}},
            )
        except AppStoreConnectError as error:
            print(f"Skipped What's New ({error}); the first version of an app has none.")


def open_review_submission(api, app_id):
    pending = api.get(
        "/v1/reviewSubmissions",
        **{"filter[app]": app_id, "filter[platform]": "IOS", "filter[state]": "READY_FOR_REVIEW"},
    )["data"]
    if pending:
        return pending[0]["id"]
    created = api.post(
        "/v1/reviewSubmissions",
        {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    return created["data"]["id"]


def submit_version_for_review(api, app_id, version_id):
    submission_id = open_review_submission(api, app_id)
    api.post(
        "/v1/reviewSubmissionItems",
        {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                },
            }
        },
    )
    api.patch(
        f"/v1/reviewSubmissions/{submission_id}",
        {"data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}},
    )


def main():
    version = os.environ["VERSION"].removeprefix("v")
    build_number = os.environ["BUILD_NUMBER"]
    notes = f"See https://github.com/pablopunk/spotifin/releases/tag/v{version}"
    api = AppStoreConnect.from_environment()
    app_id = api.app_id_for_bundle(BUNDLE_ID)
    build_id = wait_for_processed_build(api, app_id, version, build_number)
    version_id = upsert_notarization_version(api, app_id, version, build_id)
    set_whats_new_unless_first_version(api, version_id, notes)
    submit_version_for_review(api, app_id, version_id)
    print(f"Submitted Spotifin {version} ({build_number}) for Notarization")


if __name__ == "__main__":
    main()
