#!/bin/zsh
set -euo pipefail

archive=${1:?Usage: scripts/notarize-release.sh <archive.zip>}
profile=${FOLIOFOLD_NOTARY_PROFILE:?Set FOLIOFOLD_NOTARY_PROFILE to a keychain profile name}

xcrun notarytool submit "${archive}" --keychain-profile "${profile}" --wait
temporary_directory=$(mktemp -d)
trap 'rm -rf "${temporary_directory}"' EXIT
ditto -x -k "${archive}" "${temporary_directory}"
app="${temporary_directory}/FolioFold.app"
test -n "${app}"
test -d "${app}"
xcrun stapler staple "${app}"
spctl --assess --type execute --verbose=2 "${app}"
ditto -c -k --keepParent --sequesterRsrc "${app}" "${archive}"
shasum -a 256 "${archive}" > "${archive}.sha256"
