#!/usr/bin/env bash
# Reproducible test: structured [@rpc] values (records, variants, tuples, lists,
# options) round-trip through the native server's generated codecs.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/out/rpc-data}"
entry="$root/backend/tests/apps-ws/wsdata.ml"
mkdir -p "$out"
eval "$(opam env)"
jslib="$(ocamlfind query websharper-javascript)"
rtlib="$(ocamlfind query websharper-runtime)"

"$root/frontend/_build/default/bin/main.exe" \
  --input "$entry" --emit-server "$out/server.ml" \
  -I "$jslib" -I "$rtlib" -I "$(ocamlc -where)"

cp "$root/runtimes/ocaml/wsrpc.ml" "$out/"
cp "$root/runtimes/ocaml/async.ml" "$out/"
(cd "$out" && ocamlfind ocamlopt -package unix,yojson -linkpkg wsrpc.ml async.ml server.ml -o rpc_server)

"$out/rpc_server" > "$out/server.log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null || true' EXIT
sleep 1
node "$root/runtimes/ocaml/client_data.mjs"
