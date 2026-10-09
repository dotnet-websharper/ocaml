#!/usr/bin/env bash
# Fast inner-loop check: build and run only the kitchen-sink app, which touches
# every major feature (StdLib/OCaml, macros, HTML combinators, events, Var/View,
# list/fn bridging). Use run-tests.sh for the full suite.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
entry="$root/backend/tests/apps-ui/kitchensink.ml"
expected="$root/backend/tests/apps-ui/kitchensink.out"
out="${1:-$root/out/kitchensink}"

bash "$root/scripts/build-ui-app.sh" "$entry" "$out" >/dev/null
actual="$(node "$root/backend/tests/apps-ui/kitchensink.mjs" "$out" 2>&1)"

if [ -f "$expected" ] && ! diff -u "$expected" <(printf '%s\n' "$actual") > /tmp/kitchensink.diff; then
  echo "FAIL kitchensink"
  sed 's/^/    /' /tmp/kitchensink.diff
  exit 1
fi
echo "PASS kitchensink"
