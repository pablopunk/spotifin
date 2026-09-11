#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${VERSION:?Missing VERSION}"
version="${version#v}"
build_number="${BUILD_NUMBER:?Missing BUILD_NUMBER}"
output="$root/dist"

package_variant() {
  local name="$1"
  local downtify="$2"
  local workspace
  workspace="$(mktemp -d)"

  flutter build ios \
    --release \
    --no-codesign \
    --build-name "$version" \
    --build-number "$build_number" \
    --dart-define="SPOTIFIN_DOWNTIFY=$downtify"
  mkdir -p "$workspace/Payload"
  ditto "$root/build/ios/iphoneos/Runner.app" "$workspace/Payload/Runner.app"
  ditto -c -k --sequesterRsrc "$workspace" "$output/Spotifin-$version-ios-$name.ipa"
  rm -rf "$workspace"
}

cd "$root"
mkdir -p "$output"
package_variant full true
package_variant apple false
