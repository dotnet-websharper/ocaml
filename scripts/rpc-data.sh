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

# Fail fast if the port is already taken (avoids silent cross-talk with a
# leftover server).
if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:8123 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "port 8123 is already in use; stop the listener and retry" >&2
  exit 1
fi

"$out/rpc_server" > "$out/server.log" 2>&1 &
pid=$!
cleanup() { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
sleep 1
node "$root/runtimes/ocaml/client_data.mjs"
