#!/bin/zsh
set -euo pipefail

version=${1:?Usage: scripts/publish-release.sh <version>}
tag="v${version}"
arm="dist/FolioFold-${version}-arm64.zip"
intel="dist/FolioFold-${version}-x86_64.zip"

for file in "${arm}" "${arm}.sha256" "${intel}" "${intel}.sha256"; do
  test -s "${file}"
done
(cd dist && shasum -a 256 -c "$(basename "${arm}.sha256")")
(cd dist && shasum -a 256 -c "$(basename "${intel}.sha256")")
git diff --quiet
git diff --cached --quiet
git tag --list "${tag}" | grep -qx "${tag}" || git tag -a "${tag}" -m "FolioFold ${tag}"
git push origin "${tag}"
gh release create "${tag}" "${arm}" "${arm}.sha256" "${intel}" "${intel}.sha256" --verify-tag --generate-notes --title "FolioFold ${tag}"
print "Published ${tag}."
