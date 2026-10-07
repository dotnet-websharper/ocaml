#!/usr/bin/env bash
# Build a wsocaml app that consumes generated WebSharper bindings from an
# installed opam package or a package lib directory.
#   build-ws-app.sh <binding-lib-dir> <entry.ml> [out-dir]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fe="$root/frontend/_build/default/bin/main.exe"
be="$root/backend/bin/Debug/net10.0/WebSharper.OCaml.dll"
ref="$root/backend/bin/Debug/net10.0/WebSharper.JavaScript.dll"
bindir="$1"
entry="$2"
out="${3:-$root/out}"
mkdir -p "$out"
s="$(ocamlc -where)"

low_first() { echo "$(echo "${1:0:1}" | tr 'A-Z' 'a-z')${1:1}"; }

# 1) type-check the generated bindings -> .cmi in a scratch dir (never write to
#    the installed package directory)
work="$out/.deps"
mkdir -p "$work"
cp "$bindir"/*.ml "$work/"
(cd "$work" && ocamldep -sort *.ml 2>/dev/null | tr ' ' '\n' | grep -v '^$') > "$work/order.txt"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  (cd "$work" && ocamlc -c -I "$s" "$f")
done < "$work/order.txt"

# 2) compile the entry to IR to discover required modules
"$fe" --input "$entry" --output "$out/Main.wsir.json" --unit Main -I "$work" -I "$s"

globals="$(python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['requiredGlobals']))" "$out/Main.wsir.json")"

# 3) compile each required binding module to JS
for g in $globals; do
  [ "$g" = "Main" ] && continue
  f="$work/$(low_first "$g").ml"
  [ -f "$f" ] || continue
  "$fe" --input "$f" --output "$out/$g.wsir.json" --unit "$g" -I "$work" -I "$s"
  dotnet "$be" --ir "$out/$g.wsir.json" --output "$out" --reference "$ref" --compact
done

# 4) compile the entry to JS
dotnet "$be" --ir "$out/Main.wsir.json" --output "$out" --reference "$ref" --compact

# 5) stdlib shims
for shim in "$root"/backend/tests/Stdlib*.js; do
  [ -f "$shim" ] || continue
  cp "$shim" "$out/"
done

printf '{ "type": "module" }\n' > "$out/package.json"
echo "built $out/Main.js"
