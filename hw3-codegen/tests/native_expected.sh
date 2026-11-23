#!/usr/bin/env bash
# Run a test with host gcc and print the expected Arduino log (the reference for .expected)
#   tests/native_expected.sh <file.c>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
gcc -w -std=gnu89 -include "$here/native_harness.h" -o "$tmp/prog" "$1"
"$tmp/prog"
