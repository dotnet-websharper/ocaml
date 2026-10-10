#!/usr/bin/env bash
# Reproducible demo: the client (JS) reaches the `[@rpc]` handler running in a
# native OCaml server over HTTP.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/out/rpc-demo}"
mkdir -p "$out"

# 1. Client bundle (OCaml -> JS).
bash "$root/scripts/build-js-app.sh" "$root/backend/tests/apps/wsrpc.ml" "$out/client"

# 2. Native OCaml RPC server.
(cd "$root/runtimes/ocaml" && eval "$(opam env)" && \
   ocamlfind ocamlopt -package unix,yojson -linkpkg wsrpc.ml demo_server.ml -o "$out/rpc_server")

# 3. Start the server, drive the client's RPC over HTTP, stop the server.
"$out/rpc_server" > "$out/server.log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null || true' EXIT
sleep 1
node "$root/runtimes/ocaml/client_http.mjs" "$out/client"
