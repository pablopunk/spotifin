---
name: release-notes
description: Write and publish GitHub release notes for a Spotifin version. Use when the user asks for release notes or a v* tag is being deployed.
---

# Release notes

The Release workflow (`.github/workflows/release.yml`) builds every platform when a `v*` tag is pushed, then creates the GitHub release with generated notes. The release does not exist until that run succeeds, so the notes are edited in afterwards.

## Workflow

1. Find what ships: `git fetch --tags origin`, newest tag from `git tag --sort=-creatordate`, then `git log --oneline vPREV..vNEW`. Read the commits, not only the messages, for user-facing changes.
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
5. Stage the body in a temp file. Apply it once the release exists:

   ```sh
   gh run watch <run-id> --exit-status --interval 45 \
     && gh release edit vX.Y.Z --title "vX.Y.Z - <Name>" --notes-file <path>
   ```

   Run this in the background while CI builds; `gh release edit` fails until CI creates the release.
