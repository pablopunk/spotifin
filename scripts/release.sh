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

if ! git rev-parse "$tag" >/dev/null 2>&1; then
  sed "s/^version: .*/version: $version+1/" pubspec.yaml > pubspec.yaml.tmp
  mv pubspec.yaml.tmp pubspec.yaml
  if ! git diff --quiet -- pubspec.yaml; then
    git add pubspec.yaml
    git commit -m "Release $version"
  fi
  git tag "$tag"
fi

git push origin "$(git branch --show-current)"
git push origin "$tag"

echo "CI will publish all platform artifacts at:"
echo "https://github.com/pablopunk/spotifin/releases/tag/$tag"
