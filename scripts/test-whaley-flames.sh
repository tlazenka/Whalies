#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -pedantic \
  "$ROOT/scripts/tests/whaley-flames.c" -lm -o "$WORK/flames"
"$WORK/flames"
