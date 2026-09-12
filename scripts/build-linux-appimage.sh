#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${VERSION:?Missing VERSION}"
version="${version#v}"
build_number="${BUILD_NUMBER:?Missing BUILD_NUMBER}"
architecture="${ARCHITECTURE:?Missing ARCHITECTURE}"
flutter_architecture="${FLUTTER_ARCHITECTURE:?Missing FLUTTER_ARCHITECTURE}"
bundle="$root/build/linux/$flutter_architecture/release/bundle"
output="$root/dist/Spotifin-$version-linux-$architecture.AppImage"
workspace="$(mktemp -d)"
app_dir="$workspace/Spotifin.AppDir"
appimagetool="$workspace/appimagetool.AppImage"

cleanup() {
  rm -rf "$workspace"
}
trap cleanup EXIT

cd "$root"
flutter build linux \
  --release \
  --build-name "$version" \
  --build-number "$build_number" \
  --dart-define=SPOTIFIN_DOWNTIFY=true

mkdir -p "$app_dir/usr/bin" "$app_dir/usr/share/icons/hicolor/512x512/apps" "$root/dist"
cp -a "$bundle/." "$app_dir/usr/bin/"
cp "$root/assets/branding/app_icon.png" "$app_dir/usr/share/icons/hicolor/512x512/apps/spotifin.png"
ln -s usr/share/icons/hicolor/512x512/apps/spotifin.png "$app_dir/spotifin.png"

cat > "$app_dir/AppRun" <<'EOF'
#!/usr/bin/env bash
set -e
app_dir="$(dirname "$(readlink -f "$0")")"
exec "$app_dir/usr/bin/spotifin" "$@"
EOF
chmod +x "$app_dir/AppRun"

cat > "$app_dir/spotifin.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Spotifin
Comment=Jellyfin music player
Exec=spotifin
Icon=spotifin
Categories=AudioVideo;Audio;Player;
Terminal=false
X-AppImage-Version=$version
EOF

curl --fail --location --retry 3 \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$architecture.AppImage" \
  --output "$appimagetool"

case "$architecture" in
  x86_64) expected_sha256="a6d71e2b6cd66f8e8d16c37ad164658985e0cf5fcaa950c90a482890cb9d13e0" ;;
  aarch64) expected_sha256="1b00524ba8c6b678dc15ef88a5c25ec24def36cdfc7e3abb32ddcd068e8007fe" ;;
  *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
esac
echo "$expected_sha256  $appimagetool" | sha256sum -c - >/dev/null

chmod +x "$appimagetool"
ARCH="$architecture" "$appimagetool" --appimage-extract-and-run --no-appstream "$app_dir" "$output"
chmod +x "$output"
