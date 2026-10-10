#!/usr/bin/env bash
# M5: a [@website] sitelet; --emit-server generates a native server that
# server-renders pages (with injected scripts) and answers RPC.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/out/site-demo}"
entry="$root/backend/tests/apps-site/wssite.ml"
mkdir -p "$out"
eval "$(opam env)"
q() { ocamlfind query "$1" 2>/dev/null || true; }
ui="$(q websharper-ui)"; jsl="$(q websharper-javascript)"; rt="$(q websharper-runtime)"; sl="$(q websharper-stdlib)"

# Client-facing server-API .cmi (typechecked against the generated WebSharper_UI).
cmi="$out/cmi"; mkdir -p "$cmi"
cp "$root/runtimes/server-api/webSharper_Server.mli" "$root/runtimes/server-api/webSharper_ClientServer.mli" "$cmi/"
(cd "$cmi" && ocamlc -c webSharper_Server.mli -I "$ui" -I "$jsl" -I "$rt" -I "$sl" -I "$(ocamlc -where)" \
  && ocamlc -c webSharper_ClientServer.mli -I "$ui" -I "$jsl" -I "$rt" -I "$sl" -I "$(ocamlc -where)")

# Client bundle (the [@client]-ish parts; here just the module) + native server.
WS_EXTRA_INC="$cmi" bash "$root/scripts/build-ui-app.sh" "$entry" "$out/client" >/dev/null
"$root/frontend/_build/default/bin/main.exe" \
  --input "$entry" --emit-server "$out/server.ml" --unit Main --static "$out/client" \
  -I "$cmi" -I "$ui" -I "$jsl" -I "$rt" -I "$sl" -I "$(ocamlc -where)"

cp "$root/runtimes/ocaml/ssr.ml" \
   "$root/runtimes/ocaml/wsrpc.ml" "$root/runtimes/ocaml/webSharper_Server.ml" \
   "$root/runtimes/ocaml/webSharper_ClientServer.ml" \
   "$root/runtimes/ocaml/async.ml" "$root/runtimes/ui-server/webSharper_UI.ml" "$out/"
(cd "$out" && ocamlfind ocamlopt -package unix,yojson -linkpkg wsrpc.ml ssr.ml async.ml webSharper_UI.ml webSharper_ClientServer.ml webSharper_Server.ml server.ml -o server)

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
node "$root/runtimes/ocaml/site_client.mjs" "$out/client"
