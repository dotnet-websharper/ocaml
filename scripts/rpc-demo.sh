#!/usr/bin/env bash
# Reproducible demo: the client (JS) reaches a `[@rpc]` handler running in a
# native OCaml server, generated from the same source, over HTTP.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/out/rpc-demo}"
entry="$root/backend/tests/apps-ws/wssplit.ml"
mkdir -p "$out"
eval "$(opam env)"
jslib="$(ocamlfind query websharper-javascript)"
rtlib="$(ocamlfind query websharper-runtime)"

# 1. Client bundle (OCaml -> JS) against the generated bindings.
bash "$root/scripts/build-ws-app.sh" "$jslib" "$entry" "$out/client" >/dev/null

# 2. Native server source, generated from the same file (server-only + [@rpc]).
#    Type-checked against the generated bindings; the emitted program links our
#    native runtime (`wsrpc.ml`) and native `Async` (`async.ml`).
"$root/frontend/_build/default/bin/main.exe" \
  --input "$entry" --emit-server "$out/server.ml" \
  -I "$jslib" -I "$rtlib" -I "$(ocamlc -where)"

# 3. Compile the native server.
cp "$root/runtimes/ocaml/wsrpc.ml" "$out/"
cp "$root/runtimes/ocaml/async.ml" "$out/"
(cd "$out" && ocamlfind ocamlopt -package unix,yojson -linkpkg wsrpc.ml async.ml server.ml -o rpc_server)

# 4. Start the server, drive the client's RPC over HTTP, stop the server.
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
node "$root/runtimes/ocaml/client_http.mjs" "$out/client"
