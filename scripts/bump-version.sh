#!/usr/bin/env bash
set -euo pipefail

VERSION="$1"
if [[ -z "$VERSION" ]]; then
  echo "Error: version is required" >&2
  exit 1
fi

# pubspec.yaml: bump version and increment the +N build number
build=1
if grep -q '^version: .*+' pubspec.yaml; then
  build=$(grep '^version: ' pubspec.yaml | sed 's/.*+//')
  build=$((build + 1))
fi
sed -i "s/^version: .*/version: ${VERSION}+${build}/" pubspec.yaml
