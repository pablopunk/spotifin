#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${VERSION:-$(awk '/^version:/{sub(/\+.*/, "", $2); print $2}' "$root/pubspec.yaml")}"
version="${version#v}"
build_number="${BUILD_NUMBER:-1}"
signing_identity="${SIGN_IDENTITY:-Developer ID Application}"
app="$root/build/macos/Build/Products/Release/Spotifin.app"
output="$root/dist"
archive="$output/Spotifin-$version-mac-universal.zip"
notarization_archive="$output/Spotifin-$version-notarization.zip"

: "${APPLE_ID:?Missing APPLE_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Missing APPLE_APP_SPECIFIC_PASSWORD}"
: "${APPLE_TEAM_ID:?Missing APPLE_TEAM_ID}"

cd "$root"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build macos --release --build-name "$version" --build-number "$build_number"
# Sparkle's nested helpers ship ad-hoc signed; re-sign them inside-out or notarization rejects the app.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" ]]; then
  for component in \
    "$sparkle/Versions/B/XPCServices/Installer.xpc" \
    "$sparkle/Versions/B/XPCServices/Downloader.xpc" \
    "$sparkle/Versions/B/Autoupdate" \
    "$sparkle/Versions/B/Updater.app"; do
    codesign \
      --force \
      --options runtime \
      --timestamp \
      --preserve-metadata=entitlements \
      --sign "$signing_identity" \
      "$component"
  done
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --preserve-metadata=entitlements \
    --sign "$signing_identity" \
    "$sparkle"
fi
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$signing_identity" \
  --entitlements "$root/macos/Runner/Release.entitlements" \
  "$app"

codesign --verify --deep --strict --verbose=2 "$app"
codesign -dv --verbose=4 "$app" 2>&1 | grep -F 'Authority=Developer ID Application'
codesign -dv --verbose=4 "$app" 2>&1 | grep -F 'flags=' | grep -F 'runtime'
if codesign -d --entitlements :- "$app" 2>/dev/null | grep -Fq 'com.apple.security.get-task-allow'; then
  echo 'Release signature contains get-task-allow.' >&2
  exit 1
fi

mkdir -p "$output"
rm -f "$archive" "$notarization_archive" "$output/SHA256SUMS" "$output/appcast.xml"
ditto -c -k --sequesterRsrc --keepParent "$app" "$notarization_archive"
xcrun notarytool submit "$notarization_archive" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  VERSION="$version" "$root/scripts/generate-appcast.sh"
fi
cd "$output"
shasum -a 256 "$(basename "$archive")" > SHA256SUMS
rm -f "$notarization_archive"
