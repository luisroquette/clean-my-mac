#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

/usr/bin/plutil -lint Resources/Info.plist
/usr/bin/env node Scripts/test-web-demo.mjs
swift test
./Scripts/make-app.sh
./Scripts/check-public-release.sh
/usr/bin/codesign --verify --deep --strict "dist/Clean My Mac.app"
