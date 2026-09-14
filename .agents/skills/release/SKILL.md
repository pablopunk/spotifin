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

   One bullet per area with an emoji and a bold label; write for users, not as a commit dump; mention CI, license, and web changes too. Keep the summary true for the whole release.
5. Stage the body in a temp file, then publish it in the background:

   ```sh
   gh run watch <run-id> --exit-status --interval 45 \
     && gh release edit vX.Y.Z --title "vX.Y.Z - <Name>" --notes-file <path>
   ```

   `gh release edit` fails until CI creates the release, so start this only after the notes are final.
