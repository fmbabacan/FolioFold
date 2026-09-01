#!/bin/zsh
set -euo pipefail

version=${1:?Usage: scripts/generate-distribution-metadata.sh <version> [build]}
build=${2:-${version}}
account=${SPARKLE_KEY_ACCOUNT:-FolioFold}
sign_update=${SPARKLE_SIGN_UPDATE:-$(find .build -type f -perm -111 -name sign_update -print -quit)}
arm="dist/FolioFold-${version}-arm64.zip"
intel="dist/FolioFold-${version}-x86_64.zip"
test -f "${arm}"
test -f "${intel}"
test -x "${sign_update}"
arm_signature=$("${sign_update}" --account "${account}" -p "${arm}")
intel_signature=$("${sign_update}" --account "${account}" -p "${intel}")
arm_length=$(stat -f%z "${arm}")
intel_length=$(stat -f%z "${intel}")
arm_sha=$(shasum -a 256 "${arm}" | awk '{print $1}')
intel_sha=$(shasum -a 256 "${intel}" | awk '{print $1}')
escape() { print -nr -- "$1" | sed 's/[\\&|]/\\&/g' }
arm_signature=$(escape "${arm_signature}")
intel_signature=$(escape "${intel_signature}")
generate_appcast() {
  local architecture=$1
  local architecture_name=$2
  local length=$3
  local signature=$4
  sed -e "s|@VERSION@|${version}|g" -e "s|@BUILD@|${build}|g" -e "s|@ARCHITECTURE@|${architecture}|g" -e "s|@ARCHITECTURE_NAME@|${architecture_name}|g" -e "s|@LENGTH@|${length}|g" -e "s|@SIGNATURE@|${signature}|g" Distribution/Sparkle/appcast.xml.template > "appcast-${architecture}.xml"
  xmllint --noout "appcast-${architecture}.xml"
  grep -Fq 'sparkle:edSignature=' "appcast-${architecture}.xml"
}
generate_appcast arm64 "Apple Silicon" "${arm_length}" "${arm_signature}"
generate_appcast x86_64 Intel "${intel_length}" "${intel_signature}"
sed -e "s/VERSION/${version}/g" -e "s/ARM64_SHA256/${arm_sha}/g" -e "s/X86_64_SHA256/${intel_sha}/g" Distribution/Homebrew/foliofold.rb.template > dist/foliofold.rb
grep -Fq 'version "'"${version}"'"' dist/foliofold.rb
! grep -Eq 'VERSION|ARM64_SHA256|X86_64_SHA256' dist/foliofold.rb
print "Generated appcast-arm64.xml, appcast-x86_64.xml, and dist/foliofold.rb"
