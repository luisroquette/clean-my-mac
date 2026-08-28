#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

required=(README.md LICENSE SECURITY.md VERSION docs/index.html docs/styles.css docs/script.js docs/img/app-popover.webp)
for path in "${required[@]}"; do
    [[ -f "$path" ]] || { print -u2 "Missing public file: $path"; exit 1; }
done

if command -v rg >/dev/null 2>&1; then
    if rg -n -g '!check-public-release.sh' '/Users/luisroquette/' Sources Scripts Resources Tests Package.swift; then
        print -u2 "Absolute user path found in public source"
        exit 1
    fi
elif /usr/bin/grep -R -n '/Users/luisroquette/' Sources Resources Tests Package.swift Scripts/make-app.sh Scripts/preflight.sh Scripts/package-release.sh; then
    print -u2 "Absolute user path found in public source"
    exit 1
fi

[[ "$(<VERSION)" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)" ]] || {
    print -u2 "VERSION and Info.plist disagree"
    exit 1
}
