#!/usr/bin/env bash
# Server-side rendering of a *compiled* view: the same OCaml view source is
# rendered server-side (via the native Wsui_server shadow) and hydrated client-side.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/out/ssr-demo}"
entry="$root/backend/tests/apps-ui/wsclient.ml"
mkdir -p "$out"
eval "$(opam env)"

q() { ocamlfind query "$1" 2>/dev/null || true; }
ui_lib="$(q websharper-ui)"; js_lib="$(q websharper-javascript)"
rt_lib="$(q websharper-runtime)"; sl_lib="$(q websharper-stdlib)"

# 1. Client bundle (the [@client] view).
bash "$root/scripts/build-ui-app.sh" "$entry" "$out/client" >/dev/null

# 2. Native server generated from the same source: it renders the view (SSR) and
#    serves the page.
"$root/frontend/_build/default/bin/main.exe" \
  --input "$entry" --emit-server "$out/server.ml" --unit Main \
  -I "$ui_lib" -I "$js_lib" -I "$rt_lib" -I "$sl_lib" -I "$(ocamlc -where)"

# 3. Compile the native server (SSR renderer + UI shadow + HTTP server).
cp "$root/runtimes/ocaml/ssr.ml" "$root/runtimes/ui-server/webSharper_UI.ml" "$root/runtimes/ocaml/wsrpc.ml" "$out/"
(cd "$out" && ocamlfind ocamlopt -package unix,yojson,websharper-template,websharper-javascript,websharper-stdlib -linkpkg ssr.ml webSharper_UI.ml wsrpc.ml server.ml -o server)

# 4. Serve, then drive: fetch the page, hydrate in jsdom, click.
# Fail fast if the port is already taken (avoids silent cross-talk with a
# leftover server).
if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:8123 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "port 8123 is already in use; stop the listener and retry" >&2
  exit 1
fi

"$out/server" > "$out/server.log" 2>&1 &
pid=$!
cleanup() { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
sleep 1
node "$root/runtimes/ocaml/ssr_client.mjs" "$out/client"
