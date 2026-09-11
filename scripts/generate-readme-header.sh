#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

find_chrome() {
  if [[ -n "${CHROME_BIN:-}" && -x "$CHROME_BIN" ]]; then
    printf '%s\n' "$CHROME_BIN"
    return
  fi

  for candidate in google-chrome chromium chromium-browser "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return
    fi
  done

  printf '%s\n' "Chrome or Chromium is required" >&2
  return 1
}

command -v magick >/dev/null 2>&1 || {
  printf '%s\n' "ImageMagick is required" >&2
  exit 1
}

chrome="$(find_chrome)"
temp_dir="$(mktemp -d "assets/.readme-header.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT

cat >"$temp_dir/header.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <style>
      @font-face {
        font-family: Manrope;
        src: url("../fonts/Manrope-VariableFont_wght.ttf");
      }

      html, body {
        margin: 0;
        background: transparent;
      }

      .brand {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        height: 34px;
      }

      img {
        width: 34px;
        height: 34px;
      }

      span {
        color: transparent;
        background: linear-gradient(90deg, #39f4d1, #33bfff, #9b68ff);
        background-clip: text;
        font: 800 18px/1 Manrope, "Helvetica Neue", Helvetica, Arial, sans-serif;
      }
    </style>
  </head>
  <body>
    <div class="brand">
      <img src="../branding/app_icon.png" alt="">
      <span>Spotifin</span>
    </div>
  </body>
</html>
HTML

"$chrome" \
  --headless \
  --disable-gpu \
  --hide-scrollbars \
  --default-background-color=00000000 \
  --force-device-scale-factor=3 \
  --window-size=500,200 \
  --screenshot="$temp_dir/header.png" \
  "file://$PWD/$temp_dir/header.html" \
  >/dev/null 2>&1

magick "$temp_dir/header.png" -trim +repage assets/readme-header.png
