#!/bin/sh
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

grep -Fq 'run: ./Scripts/preflight.sh' .github/workflows/ci.yml
grep -Fq 'exec ./Scripts/preflight.sh' Scripts/pre-push.sh

echo "Preflight parity: OK"
