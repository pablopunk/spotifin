#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "$root/.env.release" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$root/.env.release"
  set +a
fi

: "${APPLE_ID:?Missing APPLE_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Missing APPLE_APP_SPECIFIC_PASSWORD}"
: "${APPLE_TEAM_ID:?Missing APPLE_TEAM_ID}"
: "${MACOS_CERT_P12_PATH:?Missing MACOS_CERT_P12_PATH}"
: "${MACOS_CERT_PASSWORD:?Missing MACOS_CERT_PASSWORD}"

[[ -f "$MACOS_CERT_P12_PATH" ]]
command -v gh >/dev/null

gh secret set APPLE_ID --body "$APPLE_ID"
gh secret set APPLE_APP_SPECIFIC_PASSWORD --body "$APPLE_APP_SPECIFIC_PASSWORD"
gh secret set APPLE_TEAM_ID --body "$APPLE_TEAM_ID"
gh secret set MACOS_CERT_PASSWORD --body "$MACOS_CERT_PASSWORD"
base64 < "$MACOS_CERT_P12_PATH" | gh secret set MACOS_CERT_P12_BASE64

gh secret list
