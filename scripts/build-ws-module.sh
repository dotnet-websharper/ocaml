#!/usr/bin/env bash
# Compile a single OCaml unit (no WebSharper bindings) to JavaScript.
#   build-ws-module.sh <src.ml> <Unit> [out-dir]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fe="$root/frontend/_build/default/bin/main.exe"
be="$root/backend/bin/Debug/net10.0/WebSharper.OCaml.dll"
src="$1"
unit="$2"
out="${3:-$root/out}"
mkdir -p "$out"
s="$(ocamlc -where)"

"$fe" --input "$src" --output "$out/$unit.wsir.json" --unit "$unit" -I "$(dirname "$src")" -I "$s"
dotnet "$be" --ir "$out/$unit.wsir.json" --output "$out" --compact

for shim in "$root"/backend/tests/Stdlib*.js; do
  [ -f "$shim" ] || continue
  cp "$shim" "$out/"
done

printf '{ "type": "module" }\n' > "$out/package.json"
echo "built $out/$unit.js"
