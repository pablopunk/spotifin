---
name: release
description: Cut a Spotifin release from a bump word (patch/minor/major) and write its GitHub release notes. Use when the user says "release patch/minor/major" or asks for release notes.
---

# Release

`scripts/release.sh x.y.z` refuses a dirty tree, writes `version: X.Y.Z+1` into `pubspec.yaml`, commits it as `Release X.Y.Z`, tags `vX.Y.Z`, and pushes the branch and tag. The Release workflow then builds every platform and creates the GitHub release with generated notes. The release does not exist until that run succeeds, so the real notes are edited in afterwards.

## Cut

1. `git fetch --tags origin`; read the latest tag with `git tag --sort=-v:refname | head -1`.
2. Bump it for the word used — *patch* (`0.1.4` → `0.1.5`), *minor* (`0.1.4` → `0.2.0`), *major* (`0.1.4` → `1.0.0`).
3. Announce the computed version, then run `./scripts/release.sh x.y.z`. The script prints the release URL; get the run id with `gh run list --workflow Release --limit 1`.

## Notes

1. While CI builds, gather what ships: `git log --oneline vPREV..vNEW` (skip the `Release` bump commit). Read the commits, not only the messages, for user-facing changes.
2. Copy the house style from `gh release view vPREV`.
3. Ask Pablo to pick the release name: 2–4 words (*Sound on*, *Tuned up*, *Right at home*). Offer a few options.
4. Draft the body:

   ```markdown
   ## Spotifin X.Y.Z — <Name>

   <one sentence summary of the release>.

   - 🎵 **Area** — user-facing change.
   - …

   Verify with `SHA256SUMS`. **Full changelog**: https://github.com/pablopunk/spotifin/compare/vPREV...vNEW
   ```

   One bullet per area with an emoji and a bold label; write for users, not as a commit dump; include CI, license, and web changes when present. Keep the summary true for the whole release.
5. Stage the body in a temp file, then publish it in the background:

   ```sh
   gh run watch <run-id> --exit-status --interval 45 \
     && gh release edit vX.Y.Z --title "vX.Y.Z - <Name>" --notes-file <path>
   ```

   `gh release edit` fails until CI creates the release, so start this only after the notes are final.

## macOS auto-update

CI signs `dist/appcast.xml` with Sparkle on every tag release when the `SPARKLE_PRIVATE_KEY` secret exists; the publish job uploads it next to the zip. Nothing is manual per release.

One-time setup:

1. Run a macOS build once (`flutter build macos --debug` is enough), so `macos/Pods/Sparkle/bin/generate_keys` exists.
2. `dart run auto_updater:generate_keys` and replace the `SUPublicEDKey` placeholder in `macos/Runner/Info.plist` with the printed public key.
3. `security find-generic-password -a ed25519 -s "https://sparkle-project.org" -w` prints the private key. Store it as the `SPARKLE_PRIVATE_KEY` repository secret and keep an offline backup: losing it breaks auto-update for every install that ships with the current public key.
4. `scripts/generate-appcast.sh` exits with an error while `SUPublicEDKey` is still the placeholder, so a tag release fails instead of publishing an unsigned feed.

## iOS (AltStore PAL)

Nothing is manual per release. On every tag, the `ios-notarization` job builds the full app (with Downtify), uploads it to App Store Connect as build `github.run_number`, and submits it for Notarization. Apple's notarization review takes hours to a day or two. Every 3 hours, the `sync` workflow in `pablopunk/altstore` finds the approved version, uploads its files to a release in that repo and adds it to `apps.json`. AltStore PAL then offers the update to users.

- The job does not block the GitHub release; a red `ios-notarization` only means iOS is not out yet.
- If the job fails after the upload step, never re-run it: the same build number is rejected. Fix the cause, then submit the uploaded build from a local checkout with `VERSION=vX.Y.Z BUILD_NUMBER=<run number> ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_PRIVATE_KEY="$(cat AuthKey_….p8)" python3 scripts/submit-ios-notarization.py` (needs `pyjwt[crypto]`).
- After Apple approves, `gh workflow run sync.yml -R pablopunk/altstore` publishes it without waiting for the next sync.
- Check the state in App Store Connect (Spotifin → iOS App) or with `gh run list -R pablopunk/altstore --workflow sync.yml --limit 3`.

The reviewer signs in to the demo Jellyfin at `https://spotifin-demo.notflix.us` (user `reviewer`) and can add songs through the demo Downtify at `https://downtify-demo.notflix.us`. Both run in the homelab stack `spotifin-demo` with CC BY-SA music only, and must be up while a version is in review.

One-time setup, already done: the `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY` secrets in both repos, the app's metadata, screenshots, App Privacy and review notes in App Store Connect, the AltStore marketplace token, and the EU trader (DSA) declaration in App Store Connect → Business.
