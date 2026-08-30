#!/bin/zsh
set -euo pipefail

architecture=${1:-$(uname -m)}
version=${FOLIOFOLD_VERSION:-0.1.0}
identity=${FOLIOFOLD_SIGNING_IDENTITY:--}
output_root=${FOLIOFOLD_OUTPUT_DIR:-dist}
app_name=FolioFold
staging_root="${output_root}/.staging-${version}-${architecture}"
app_bundle="${staging_root}/${app_name}.app"
contents="${app_bundle}/Contents"
macos="${contents}/MacOS"
resources="${contents}/Resources"
archive="${output_root}/${app_name}-${version}-${architecture}.zip"

rm -rf "${staging_root}" "${archive}" "${archive}.sha256"
mkdir -p "${macos}" "${resources}"
trap 'rm -rf "${staging_root}"' EXIT

swift build -c release
cp .build/release/FolioFold "${macos}/FolioFold"

cat > "${contents}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>FolioFold</string>
  <key>CFBundleIdentifier</key><string>app.foliofold.FolioFold</string>
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

codesign --force --deep --options runtime --timestamp=none --sign "${identity}" "${app_bundle}"
codesign --verify --deep --strict --verbose=2 "${app_bundle}"
ditto -c -k --keepParent --sequesterRsrc "${app_bundle}" "${archive}"

size=$(stat -f%z "${archive}")
if (( size >= 41943040 )); then
  print -u2 "Archive exceeds the 40 MB release budget: ${size} bytes"
  exit 1
fi

shasum -a 256 "${archive}" > "${archive}.sha256"
print "Created ${archive}"
print "Created ${archive}.sha256"
