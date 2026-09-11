#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
tag="v$version"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree is dirty." >&2
  exit 1
fi

git rev-parse "$tag" >/dev/null 2>&1 || git tag "$tag"
git push origin "$(git branch --show-current)"
git push origin "$tag"

echo "CI will publish the signed and notarized macOS release at:"
echo "https://github.com/pablopunk/spotifin/releases/tag/$tag"
