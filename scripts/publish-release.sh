#!/bin/zsh
set -euo pipefail

version=${1:?Usage: scripts/publish-release.sh <version>}
tag="v${version}"
arm="dist/FolioFold-${version}-arm64.zip"
intel="dist/FolioFold-${version}-x86_64.zip"
notes=$(mktemp)
trap 'rm -f "${notes}"' EXIT

for file in "${arm}" "${arm}.sha256" "${intel}" "${intel}.sha256"; do
  test -s "${file}"
done
(cd dist && shasum -a 256 -c "$(basename "${arm}.sha256")")
(cd dist && shasum -a 256 -c "$(basename "${intel}.sha256")")
git diff --quiet
git diff --cached --quiet
git tag --list "${tag}" | grep -qx "${tag}" || git tag -a "${tag}" -m "FolioFold ${tag}"
git push origin "${tag}"
printf '## Downloads\n\n- **Apple Silicon Macs:** download `FolioFold-%s-arm64.zip` for M1, M2, M3, M4, and newer Apple chips.\n- **Intel Macs:** download `FolioFold-%s-x86_64.zip`.\n\nEach ZIP has a matching `.sha256` file for integrity verification. FolioFold requires macOS 15 or later.\n' \
  "${version}" "${version}" > "${notes}"
gh release create "${tag}" "${arm}" "${arm}.sha256" "${intel}" "${intel}.sha256" --verify-tag --generate-notes --notes-file "${notes}" --title "FolioFold ${tag}"
print "Published ${tag}."
