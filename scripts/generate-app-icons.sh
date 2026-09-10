#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."
dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
dart run tool/generate_maskable_icons.dart
perl -pi -e 's/(ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = )AppIcon;/${1}YES;/' ios/Runner.xcodeproj/project.pbxproj
