#!/usr/bin/env bash
# Build a wsocaml app that uses handwritten WebSharper libraries (e.g.
# WebSharper.UI) via the WebSharper compilation pipeline (--ws-compile).
#   build-ui-app.sh <entry.ml> [out-dir]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fe="$root/frontend/_build/default/bin/main.exe"
be="$root/backend/bin/Debug/net10.0/WebSharper.OCaml.dll"
entry="$1"
out="${2:-$root/out}"
mkdir -p "$out"
s="$(ocamlc -where)"

q() { ocamlfind query "$1" 2>/dev/null || opam exec -- ocamlfind query "$1" 2>/dev/null || true; }
ui_lib="$(q websharper-ui)"
js_lib="$(q websharper-javascript)"
rt_lib="$(q websharper-runtime)"

newest() { ls "$@" 2>/dev/null | sort | tail -1; }
js_dll="$(newest "$HOME"/.nuget/packages/websharper/*/lib/netstandard2.0/WebSharper.JavaScript.dll)"
sl_dll="$(newest "$HOME"/.nuget/packages/websharper/*/lib/netstandard2.0/WebSharper.StdLib.dll)"
ui_dll="$(newest "$HOME"/.nuget/packages/websharper.ui/*/lib/netstandard2.0/WebSharper.UI.dll)"

inc=(-I "$ui_lib" -I "$js_lib" -I "$s")
[ -n "$rt_lib" ] && inc+=(-I "$rt_lib")

"$fe" --input "$entry" --output "$out/Main.wsir.json" --unit Main "${inc[@]}"
dotnet "$be" --ir "$out/Main.wsir.json" --output "$out" --ws-compile \
  --reference "$ui_dll" --reference "$sl_dll" --reference "$js_dll" --compact

for shim in "$root"/backend/tests/Stdlib*.js; do
  [ -f "$shim" ] || continue
  cp "$shim" "$out/"
done

printf '{ "type": "module" }\n' > "$out/package.json"
echo "built $out/Main.js"
