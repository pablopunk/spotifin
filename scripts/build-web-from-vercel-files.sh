#!/usr/bin/env bash
# Builds the web app from only the files Vercel receives (tracked files minus
# .vercelignore), so a path missing from the upload fails here like it does on Vercel.
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
tree="${1:-$(mktemp -d)}"
mkdir -p "$tree"

cd "$repo"
comm -23 \
  <(git ls-files | sort) \
  <(git ls-files --cached --ignored --exclude-from=.vercelignore | sort) \
  | rsync -a --files-from=- "$repo/" "$tree/"

echo "Building web from Vercel file set in $tree"
cd "$tree"
MISE_TRUSTED_CONFIG_PATHS="$tree" bash scripts/build-web.sh
