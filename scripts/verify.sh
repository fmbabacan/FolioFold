#!/bin/zsh
set -euo pipefail

swift package show-dependencies --format json | python3 -c 'import json,sys; assert json.load(sys.stdin)["dependencies"] == []'
python3 -m json.tool Sources/FolioFold/Resources/Localizable.xcstrings > /dev/null
swift test
swift build -c release
scripts/runtime-smoke.sh .build/release/FolioFold
scripts/ui-smoke.sh .build/release/FolioFold

print "FolioFold verification passed."
