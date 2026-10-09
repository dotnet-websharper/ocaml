#!/usr/bin/env bash
# Build a wsocaml app that uses handwritten WebSharper libraries (e.g.
# WebSharper.UI) via the WebSharper compilation pipeline (--ws-compile).
# Any sibling .ml files next to the entry are compiled first (facades/modules).
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
sl_lib="$(q websharper-stdlib)"

newest() { ls "$@" 2>/dev/null | sort | tail -1; }
js_dll="$(newest "$HOME"/.nuget/packages/websharper/*/lib/netstandard2.0/WebSharper.JavaScript.dll)"
sl_dll="$(newest "$HOME"/.nuget/packages/websharper/*/lib/netstandard2.0/WebSharper.StdLib.dll)"
ui_dll="$(newest "$HOME"/.nuget/packages/websharper.ui/*/lib/netstandard2.0/WebSharper.UI.dll)"

inc=(-I "$ui_lib" -I "$js_lib" -I "$s")
[ -n "$rt_lib" ] && inc+=(-I "$rt_lib")
[ -n "$sl_lib" ] && inc+=(-I "$sl_lib")
refs=(--reference "$ui_dll" --reference "$sl_dll" --reference "$js_dll")

srcdir="$(cd "$(dirname "$entry")" && pwd)"
work="$out/.deps"
mkdir -p "$work"

sibs=()
for f in "$srcdir"/*.ml; do
  [ "$f" = "$entry" ] && continue
  sibs+=("$f")
done

if [ -n "${sibs[*]:-}" ]; then
  cp "${sibs[@]}" "$work/"
  (cd "$work" && ocamldep -sort *.ml 2>/dev/null | tr ' ' '\n' | grep -v '^$') > "$work/order.txt"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    (cd "$work" && ocamlc -c -I "$s" "${inc[@]}" -I "$work" "$f")
  done < "$work/order.txt"
fi

compile_unit() {
  local src="$1" unit="$2"
  "$fe" --input "$src" --output "$out/$unit.wsir.json" --unit "$unit" "${inc[@]}" -I "$work"
  dotnet "$be" --ir "$out/$unit.wsir.json" --output "$out" --ws-compile "${refs[@]}" --compact
}

for f in ${sibs[@]+"${sibs[@]}"}; do
  n="$(basename "$f" .ml)"
  compile_unit "$f" "$(echo "${n:0:1}" | tr '[:lower:]' '[:upper:]')${n:1}"
done
compile_unit "$entry" Main

for shim in "$root"/backend/tests/Stdlib*.js; do
  [ -f "$shim" ] || continue
  cp "$shim" "$out/"
done

printf '{ "type": "module" }\n' > "$out/package.json"
echo "built $out/Main.js"
