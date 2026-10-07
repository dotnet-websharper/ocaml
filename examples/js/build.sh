#!/usr/bin/env bash
# Build the example to JavaScript. The binding package `websharper-javascript`
# is referenced from dune (see ./dune); dune passes a path inside the installed
# library so we can locate the generated sources.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
out="${1:-out}"
sample="${2:-}"

if [ -n "$sample" ]; then
  bindir="$(dirname "$sample")"
else
  bindir="$(ocamlfind query websharper-javascript 2>/dev/null || true)"
fi
if [ -z "$bindir" ]; then
  echo "websharper-javascript not found. Install it with:" >&2
  echo "  opam repo add wsocaml ./bindings && opam install websharper-javascript" >&2
  exit 1
fi

bash "$root/scripts/build-ws-app.sh" "$bindir" "$here/main.ml" "$out"
