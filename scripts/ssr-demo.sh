#!/usr/bin/env bash
# Server-side rendering: a native OCaml server renders an HTML page (with an SSR
# [@client] region); the client bundle hydrates the region in jsdom.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/out/ssr-demo}"
mkdir -p "$out"
eval "$(opam env)"

# 1. Client bundle (the [@client] view).
bash "$root/scripts/build-ui-app.sh" "$root/backend/tests/apps-ui/wsclient.ml" "$out/client" >/dev/null

# 2. Native server (SSR renderer + HTTP server + page).
cp "$root/runtimes/ocaml/ssr.ml" "$root/runtimes/ocaml/wsrpc.ml" "$root/runtimes/ocaml/ssr_server.ml" "$out/"
(cd "$out" && ocamlfind ocamlopt -package unix,yojson -linkpkg ssr.ml wsrpc.ml ssr_server.ml -o server)

# 3. Serve, then drive: fetch the page, hydrate in jsdom, click.
"$out/server" > "$out/server.log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null || true' EXIT
sleep 1
node "$root/runtimes/ocaml/ssr_client.mjs" "$out/client"
