#!/bin/zsh
set -euo pipefail

architecture=${1:-$(uname -m)}
architecture=${architecture:l}
case "${architecture}" in
  arm64|x86_64) ;;
  *)
    print -u2 "Unsupported architecture: ${architecture}"
    exit 1
    ;;
esac
version=${FOLIOFOLD_VERSION:-0.3.1}
identity=${FOLIOFOLD_SIGNING_IDENTITY:--}
output_root=${FOLIOFOLD_OUTPUT_DIR:-dist}
build_path=${FOLIOFOLD_BUILD_PATH:-.build}
app_name=FolioFold
staging_root="${output_root}/.staging-${version}-${architecture}"
app_bundle="${staging_root}/${app_name}.app"
contents="${app_bundle}/Contents"
macos="${contents}/MacOS"
resources="${contents}/Resources"
icon_source="Sources/FolioFold/Resources/AppIcon.icns"
archive="${output_root}/${app_name}-${version}-${architecture}.zip"

rm -rf "${staging_root}" "${archive}" "${archive}.sha256"
mkdir -p "${macos}" "${resources}"
trap 'rm -rf "${staging_root}"' EXIT

swift build -c release --arch "${architecture}" --build-path "${build_path}"
executable="${build_path}/release/FolioFold"
test -x "${executable}"
file "${executable}" | grep -q "${architecture}" || {
  print -u2 "Built executable does not contain expected architecture: ${architecture}"
  exit 1
}
cp "${executable}" "${macos}/FolioFold"
test -s "${icon_source}"
cp "${icon_source}" "${resources}/AppIcon.icns"

cat > "${contents}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>FolioFold</string>
  <key>CFBundleIdentifier</key><string>app.foliofold.FolioFold</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FolioFold</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>CFBundleVersion</key><string>${version}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [[ "${identity}" == "-" ]]; then
  codesign --force --deep --options runtime --timestamp=none --sign "${identity}" "${app_bundle}"
else
  codesign --force --deep --options runtime --timestamp --sign "${identity}" "${app_bundle}"
fi
codesign --verify --deep --strict --verbose=2 "${app_bundle}"
file "${macos}/FolioFold" | grep -q "${architecture}" || {
  print -u2 "Packaged application does not contain expected architecture: ${architecture}"
  exit 1
}
ditto -c -k --keepParent --sequesterRsrc "${app_bundle}" "${archive}"

size=$(stat -f%z "${archive}")
if (( size >= 41943040 )); then
  print -u2 "Archive exceeds the 40 MB release budget: ${size} bytes"
  exit 1
fi

(cd "${archive:h}" && shasum -a 256 "${archive:t}" > "${archive:t}.sha256")
print "Created ${archive}"
print "Created ${archive}.sha256"
