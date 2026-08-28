#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
version="$(<"$project_dir/VERSION")"
archive="$project_dir/release/Clean-My-Mac-$version.zip"

cd "$project_dir"
./Scripts/preflight.sh
/bin/mkdir -p release
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "dist/Clean My Mac.app" "$archive"
(cd release && /usr/bin/shasum -a 256 "Clean-My-Mac-$version.zip" > "Clean-My-Mac-$version.zip.sha256")
[[ "$(<"$archive.sha256")" == *"  Clean-My-Mac-$version.zip" ]] || {
    print -u2 "Checksum contains a non-portable path"
    exit 1
}
print "$archive"
