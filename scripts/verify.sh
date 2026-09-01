#!/bin/zsh
set -euo pipefail

swift package show-dependencies --format json | python3 -c 'import json,sys; dependencies=json.load(sys.stdin)["dependencies"]; assert len(dependencies) == 1; sparkle=dependencies[0]; assert sparkle["url"] == "https://github.com/sparkle-project/Sparkle"; assert sparkle["version"] == "2.9.6"'
python3 -m json.tool Sources/FolioFold/Resources/Localizable.xcstrings > /dev/null
scripts/localization-smoke.sh
scripts/appearance-smoke.sh
swift test
swift build -c release
scripts/runtime-smoke.sh .build/release/FolioFold
scripts/macos-ui-tests.sh .build/release/FolioFold
scripts/visual-regression.sh .build/release/FolioFold

print "FolioFold verification passed."
