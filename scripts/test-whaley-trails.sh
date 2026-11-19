#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -pedantic \
  "$ROOT/scripts/tests/whaley-trails.c" -lm -o "$WORK/trails"
"$WORK/trails"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -pedantic \
  "$ROOT/scripts/tests/whaley-trail-width.c" -lm -o "$WORK/width"
"$WORK/width"
