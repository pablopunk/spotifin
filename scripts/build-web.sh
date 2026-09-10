#!/usr/bin/env bash
set -euo pipefail

if command -v mise >/dev/null 2>&1; then
  exec mise exec -- flutter build web --release
fi

flutter_version="3.47.3"
flutter_root="${TMPDIR:-/tmp}/flutter-$flutter_version"
if [[ ! -x "$flutter_root/bin/flutter" ]]; then
  git clone --depth 1 --branch "$flutter_version" https://github.com/flutter/flutter.git "$flutter_root"
fi
exec "$flutter_root/bin/flutter" build web --release
