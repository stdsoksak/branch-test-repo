#!/usr/bin/env bash
set -euo pipefail
git checkout main
git pull --ff-only origin main
for b in develop-nd validation-nt; do
  if git ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1; then
    echo "$b already exists"
  else
    git branch "$b" main
    git push origin "$b"
  fi
done
