#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -pedantic \
  "$ROOT/scripts/tests/whaley-expressions.c" -lm -o "$WORK/expressions"
"$WORK/expressions"
