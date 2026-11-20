#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${VERSION:?Missing VERSION}"
version="${version#v}"
build_number="${BUILD_NUMBER:?Missing BUILD_NUMBER}"
team_id="${APPLE_TEAM_ID:?Missing APPLE_TEAM_ID}"
: "${ASC_KEY_ID:?Missing ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Missing ASC_ISSUER_ID}"
: "${ASC_PRIVATE_KEY:?Missing ASC_PRIVATE_KEY}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
key_path="$work/AuthKey_$ASC_KEY_ID.p8"
printf '%s\n' "$ASC_PRIVATE_KEY" > "$key_path"
archive="$work/Spotifin.xcarchive"
auth_flags=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$key_path"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

cat > "$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$team_id</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

cd "$root"
flutter build ios \
  --release \
  --config-only \
  --build-name "$version" \
  --build-number "$build_number" \
  --dart-define=SPOTIFIN_DOWNTIFY=false
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive" \
  DEVELOPMENT_TEAM="$team_id" \
  "${auth_flags[@]}"
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$work/ExportOptions.plist" \
  -exportPath "$work/export" \
  "${auth_flags[@]}"
