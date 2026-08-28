#!/usr/bin/env bash
set -euo pipefail
test -f app/message.txt
grep -q 'branch-promotion-test' app/message.txt
echo 'Application checks passed.'
