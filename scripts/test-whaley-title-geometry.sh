#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"${CC:-clang}" -std=c11 -Wall -Wextra -Werror -pedantic \
  "$ROOT/scripts/tests/whaley-title-geometry.c" -lm -o "$WORK/title-geometry"
"$WORK/title-geometry"
