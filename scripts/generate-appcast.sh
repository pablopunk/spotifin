#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${VERSION:?Missing VERSION}"
version="${version#v}"
archive="${ARCHIVE:-$root/dist/Spotifin-$version-mac-universal.zip}"
output="$root/dist/appcast.xml"
: "${SPARKLE_PRIVATE_KEY:?Missing SPARKLE_PRIVATE_KEY}"

sparkle_version="2.9.6"
sparkle_sha256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"

workspace="$(mktemp -d)"
cleanup() {
  rm -rf "$workspace"
}
trap cleanup EXIT

if [[ ! -f "$archive" ]]; then
  echo "Missing macOS archive: $archive" >&2
  exit 1
fi

tools_archive="$workspace/Sparkle-$sparkle_version.tar.xz"
curl --fail --location --retry 3 \
  "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" \
  --output "$tools_archive"
echo "$sparkle_sha256  $tools_archive" | shasum -a 256 -c - >/dev/null
tar -xJf "$tools_archive" -C "$workspace"

updates="$workspace/updates"
mkdir -p "$updates"
cp "$archive" "$updates/"

printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$workspace/bin/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "https://github.com/pablopunk/spotifin/releases/download/v$version/" \
  --link "https://github.com/pablopunk/spotifin" \
  "$updates"

if ! grep -q 'sparkle:edSignature' "$updates/appcast.xml"; then
  echo 'The appcast is unsigned: replace SUPublicEDKey in macos/Runner/Info.plist.' >&2
  exit 1
fi

cp "$updates/appcast.xml" "$output"
