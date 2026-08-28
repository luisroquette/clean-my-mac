#!/bin/sh
set -eu

root=$(git rev-parse --show-toplevel)
hook=$(git rev-parse --git-path hooks)/pre-push
mkdir -p "$(dirname "$hook")"

printf '%s\n' '#!/bin/sh' 'exec sh "$(git rev-parse --show-toplevel)/Scripts/pre-push.sh" "$@"' > "$hook"
chmod +x "$hook" "$root/Scripts/pre-push.sh"
