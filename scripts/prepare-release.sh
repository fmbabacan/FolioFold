#!/bin/zsh
set -euo pipefail

version=${1:?Usage: scripts/prepare-release.sh <version> [architecture]}
architecture=${2:-$(uname -m)}
architecture=${architecture:l}
case "${architecture}" in
  arm64|x86_64) ;;
  *)
    print -u2 "Unsupported architecture: ${architecture}"
    exit 1
    ;;
esac
identity=${FOLIOFOLD_SIGNING_IDENTITY:?Set FOLIOFOLD_SIGNING_IDENTITY to a Developer ID Application identity}
profile=${FOLIOFOLD_NOTARY_PROFILE:?Set FOLIOFOLD_NOTARY_PROFILE to a notarytool Keychain profile}

[[ "${version}" == [0-9]*.[0-9]*.[0-9]* ]]
security find-identity -v -p codesigning | grep -F "${identity}" > /dev/null
build_path=${FOLIOFOLD_BUILD_PATH:-.build-${architecture}}
FOLIOFOLD_VERSION="${version}" FOLIOFOLD_BUILD_PATH="${build_path}" scripts/package-release.sh "${architecture}"
FOLIOFOLD_NOTARY_PROFILE="${profile}" scripts/notarize-release.sh "dist/FolioFold-${version}-${architecture}.zip"
(cd dist && shasum -a 256 -c "FolioFold-${version}-${architecture}.zip.sha256")
print "Prepared notarized release asset for ${architecture}."
