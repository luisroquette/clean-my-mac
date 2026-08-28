#!/bin/sh
set -eu

while read -r _local_ref _local_sha remote_ref _remote_sha; do
  if [ "$remote_ref" = "refs/heads/main" ] && [ "${PUSH_MAIN:-}" != "1" ]; then
    echo "[pre-push] BLOQUEADO: push direto na main. Use branch + PR."
    exit 1
  fi
done

cd "$(git rev-parse --show-toplevel)"
exec ./Scripts/preflight.sh
