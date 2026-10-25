#!/usr/bin/env bash
# Build the TodoMVC example:
#   out/client  - the JS client bundle (the app) + css/
#   out/server  - the native OCaml server (sitelet), from --emit-server
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
entry="$here/todomvc.ml"
out="${1:-$here/out}"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
mkdir -p "$out"
eval "$(opam env)"

q() { ocamlfind query "$1" 2>/dev/null || true; }
ui="$(q websharper-ui)"; jsl="$(q websharper-javascript)"; rt="$(q websharper-runtime)"; sl="$(q websharper-stdlib)"
server="$(q websharper-server)"; uiserver="$(q websharper-ui-server)"; yojson="$(q yojson)"; tpl="$(q websharper-template)"

# Client-facing server-API stubs (typechecked against the generated WebSharper_UI).
cmi="$out/cmi"; mkdir -p "$cmi"
cp "$root/runtimes/server-api/webSharper_Server.mli" "$root/runtimes/server-api/webSharper_ClientServer.mli" "$cmi/"
(cd "$cmi" && ocamlc -c webSharper_Server.mli -I "$ui" -I "$jsl" -I "$rt" -I "$sl" -I "$(ocamlc -where)" \
  && ocamlc -c webSharper_ClientServer.mli -I "$ui" -I "$jsl" -I "$rt" -I "$sl" -I "$(ocamlc -where)")

# 1. JS client bundle.
WS_EXTRA_INC="$cmi" bash "$root/scripts/build-ui-app.sh" "$entry" "$out/client" >/dev/null

# Static assets served by the native server.
mkdir -p "$out/client/css"
cp "$here/css/app.css" "$out/client/css/app.css"

# 2. Native server generated from the same source (the sitelet).
"$root/frontend/_build/default/bin/main.exe" \
  --input "$entry" --emit-server "$out/server.ml" --unit Main --static "$out/client" \
  --server-include "$server" --server-include "$uiserver" --server-include "$yojson" --server-include "$tpl" --server-include "$jsl" \
  -I "$cmi" -I "$ui" -I "$jsl" -I "$rt" -I "$sl" -I "$(ocamlc -where)"

# 3. Compile it against the installed websharper-server / websharper-ui-server.
(cd "$out" && ocamlfind ocamlopt -package websharper-ui-server -linkpkg server.ml -o server)

echo "built $out/server (run it, then open http://127.0.0.1:8123/)"
