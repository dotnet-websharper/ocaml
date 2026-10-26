#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
cases="$here/cases"

update=0
build=1
for arg in "$@"; do
  case "$arg" in
    --update) update=1 ;;
    --no-build) build=0 ;;
    -h | --help)
      echo "usage: run-tests.sh [--update] [--no-build]"
      echo "  --update    regenerate .expected.js/.out goldens"
      echo "  --no-build  skip the backend build"
      exit 0
      ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! command -v node > /dev/null 2>&1; then
  echo "node is required (used for syntax checks and runtime drivers)" >&2
  exit 2
fi

if [ "$build" = 1 ]; then
  (cd "$root" && dotnet build -v q)
fi

dll="$root/bin/Debug/net10.0/WebSharper.OCaml.dll"
if [ ! -f "$dll" ]; then
  echo "backend not built: $dll" >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

for ir in "$cases"/*.wsir.json; do
  name="$(basename "$ir" .wsir.json)"
  out="$tmp/$name"
  mkdir -p "$out"

  if ! dotnet "$dll" --ir "$ir" --output "$out" --compact > "$tmp/$name.log" 2>&1; then
    echo "FAIL $name (compile)"
    sed 's/^/    /' "$tmp/$name.log"
    fail=$((fail + 1))
    continue
  fi

  js="$(ls "$out"/*.js 2>/dev/null | head -n 1 || true)"
  if [ -z "$js" ]; then
    echo "FAIL $name (no output)"
    fail=$((fail + 1))
    continue
  fi

  expected="$cases/$name.expected.js"
  if [ "$update" = 1 ]; then
    cp "$js" "$expected"
    echo "updated $name.expected.js"
  fi

  ok=1
  if [ -f "$expected" ] && ! diff -u "$expected" "$js" > "$tmp/$name.js.diff"; then
    echo "FAIL $name (js mismatch)"
    sed 's/^/    /' "$tmp/$name.js.diff"
    ok=0
  fi

  if [ "$ok" = 1 ] && ! node --check "$js" > /dev/null 2>&1; then
    echo "FAIL $name (node --check)"
    ok=0
  fi

  driver="$cases/$name.driver.mjs"
  expectedOut="$cases/$name.out"
  if [ "$ok" = 1 ] && [ -f "$driver" ]; then
    unit="$(basename "$js" .js)"
    cp "$js" "$out/$unit.mjs"
    if [ "$update" = 1 ]; then
      node "$driver" "$out/$unit.mjs" > "$expectedOut" 2>&1 || true
      echo "updated $name.out"
    fi
    if ! node "$driver" "$out/$unit.mjs" > "$tmp/$name.actual" 2>&1; then
      echo "FAIL $name (driver)"
      sed 's/^/    /' "$tmp/$name.actual"
      ok=0
    elif [ -f "$expectedOut" ] && ! diff -u "$expectedOut" "$tmp/$name.actual" > "$tmp/$name.out.diff"; then
      echo "FAIL $name (output mismatch)"
      sed 's/^/    /' "$tmp/$name.out.diff"
      ok=0
    fi
  fi

  if [ "$ok" = 1 ]; then
    echo "PASS $name"
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi
done

for d in "$cases"/*/; do
  [ -d "$d" ] || continue
  [ -n "$(ls "$d"*.wsir.json 2>/dev/null)" ] || continue
  name="$(basename "$d")"
  out="$tmp/$name"
  mkdir -p "$out"
  printf '{ "type": "module" }\n' > "$out/package.json"
  for asset in "$d"*.js; do
    [ -f "$asset" ] || continue
    cp "$asset" "$out/"
  done
  for shim in "$here"/Stdlib*.js; do
    [ -f "$shim" ] || continue
    cp "$shim" "$out/"
  done

  ok=1
  for ir in "$d"*.wsir.json; do
    if ! dotnet "$dll" --ir "$ir" --output "$out" --compact > "$tmp/$name.compile.log" 2>&1; then
      echo "FAIL $name (compile $(basename "$ir"))"
      sed 's/^/    /' "$tmp/$name.compile.log"
      ok=0
      break
    fi
  done

  if [ "$ok" = 1 ]; then
    for js in "$out"/*.js; do
      if ! node --check "$js" > /dev/null 2>&1; then
        echo "FAIL $name (node --check $(basename "$js"))"
        ok=0
      fi
    done
  fi

  if [ "$ok" = 1 ] && [ -f "$d/main.mjs" ]; then
    if [ "$update" = 1 ]; then
      node "$d/main.mjs" "$out" > "$d/expected.out" 2>&1 || true
      echo "updated $name/expected.out"
    fi
    if ! node "$d/main.mjs" "$out" > "$tmp/$name.actual" 2>&1; then
      echo "FAIL $name (driver)"
      sed 's/^/    /' "$tmp/$name.actual"
      ok=0
    elif [ -f "$d/expected.out" ] && ! diff -u "$d/expected.out" "$tmp/$name.actual" > "$tmp/$name.out.diff"; then
      echo "FAIL $name (output mismatch)"
      sed 's/^/    /' "$tmp/$name.out.diff"
      ok=0
    fi
  fi

  if [ "$ok" = 1 ]; then
    echo "PASS $name"
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi
done

apps="$here/apps"
if [ -d "$apps" ]; then
  for ml in "$apps"/*.ml; do
    [ -f "$ml" ] || continue
    aname="$(basename "$ml" .ml)"
    aout="$tmp/app_$aname"
    mkdir -p "$aout"
    if ! bash "$here/../../scripts/build-js-app.sh" "$ml" "$aout" > "$tmp/app_$aname.build" 2>&1; then
      echo "FAIL app $aname (build)"
      sed 's/^/    /' "$tmp/app_$aname.build"
      fail=$((fail + 1))
      continue
    fi
    if [ -f "$apps/$aname.mjs" ]; then
      node "$apps/$aname.mjs" "$aout" > "$tmp/app_$aname.actual" 2>&1 || true
    else
      node "$aout/Main.js" > "$tmp/app_$aname.actual" 2>&1 || true
    fi
    expectedOut="$apps/$aname.out"
    if [ "$update" = 1 ]; then
      cp "$tmp/app_$aname.actual" "$expectedOut"
      echo "updated app_$aname.out"
    fi
    if [ -f "$expectedOut" ] && ! diff -u "$expectedOut" "$tmp/app_$aname.actual" > "$tmp/app_$aname.diff"; then
      echo "FAIL app $aname (output mismatch)"
      sed 's/^/    /' "$tmp/app_$aname.diff"
      fail=$((fail + 1))
      continue
    fi
    echo "PASS app $aname"
    pass=$((pass + 1))
  done
fi

apps_ws="$here/apps-ws"
wsroot="$(cd "$here/../.." && pwd)"
if [ -d "$apps_ws" ]; then
  wslib="$(ocamlfind query websharper-javascript 2>/dev/null || opam exec -- ocamlfind query websharper-javascript 2>/dev/null || true)"
  if [ -z "$wslib" ]; then
    echo "SKIP ws apps (websharper-javascript not installed; opam repo add wsocaml ./bindings && opam install websharper-javascript)"
  else
    for ml in "$apps_ws"/*.ml; do
      [ -f "$ml" ] || continue
      aname="$(basename "$ml" .ml)"
      aout="$tmp/ws_$aname"
      mkdir -p "$aout"
      if ! bash "$here/../../scripts/build-ws-app.sh" "$wslib" "$ml" "$aout" > "$tmp/ws_$aname.build" 2>&1; then
        echo "FAIL ws $aname (build)"
        sed 's/^/    /' "$tmp/ws_$aname.build"
        fail=$((fail + 1))
        continue
      fi
      if [ -f "$apps_ws/$aname.mjs" ]; then
        node "$apps_ws/$aname.mjs" "$aout" > "$tmp/ws_$aname.actual" 2>&1 || true
      else
        node "$aout/Main.js" > "$tmp/ws_$aname.actual" 2>&1 || true
      fi
      # Optional TypeScript-declaration golden for [@export] APIs.
      dtsGolden="$apps_ws/$aname.dts"
      if [ -f "$dtsGolden" ] || [ -f "$aout/Main.d.ts" ]; then
        if [ "$update" = 1 ]; then cp "$aout/Main.d.ts" "$dtsGolden" 2>/dev/null || true; fi
        if [ -f "$dtsGolden" ] && ! diff -u "$dtsGolden" "$aout/Main.d.ts" > "$tmp/ws_$aname.dts.diff" 2>&1; then
          echo "FAIL ws $aname (.d.ts mismatch)"
          sed 's/^/    /' "$tmp/ws_$aname.dts.diff"
          fail=$((fail + 1))
          continue
        fi
      fi
      expectedOut="$apps_ws/$aname.out"
      if [ "$update" = 1 ]; then
        cp "$tmp/ws_$aname.actual" "$expectedOut"
        echo "updated ws_$aname.out"
      fi
      if [ -f "$expectedOut" ] && ! diff -u "$expectedOut" "$tmp/ws_$aname.actual" > "$tmp/ws_$aname.diff"; then
        echo "FAIL ws $aname (output mismatch)"
        sed 's/^/    /' "$tmp/ws_$aname.diff"
        fail=$((fail + 1))
        continue
      fi
      echo "PASS ws $aname"
      pass=$((pass + 1))
    done
  fi
fi

# WebSharper-binding IR fixtures (need a referenced assembly).
cases_ws="$here/cases-ws"
if [ -d "$cases_ws" ]; then
  wsref="$root/bin/Debug/net10.0/WebSharper.StdLib.dll"
  for ir in "$cases_ws"/*.wsir.json; do
    [ -f "$ir" ] || continue
    name="$(basename "$ir" .wsir.json)"
    out="$tmp/cws_$name"
    mkdir -p "$out"
    errfile="$cases_ws/$name.expected.err"
    if dotnet "$dll" --ir "$ir" --output "$out" --reference "$wsref" --compact > "$tmp/cws_$name.log" 2>&1; then
      if [ -f "$errfile" ]; then
        echo "FAIL ws-case $name (expected failure)"
        fail=$((fail + 1))
        continue
      fi
      js="$(ls "$out"/*.js 2>/dev/null | head -n 1 || true)"
      expected="$cases_ws/$name.expected.js"
      if [ "$update" = 1 ] && [ -n "$js" ]; then
        cp "$js" "$expected"
        echo "updated $name.expected.js"
      fi
      ok=1
      if [ -f "$expected" ] && ! diff -u "$expected" "$js" > "$tmp/cws_$name.diff"; then
        echo "FAIL ws-case $name (js mismatch)"
        sed 's/^/    /' "$tmp/cws_$name.diff"
        ok=0
      fi
      if [ "$ok" = 1 ] && ! node --check "$js" > /dev/null 2>&1; then
        echo "FAIL ws-case $name (node --check)"
        ok=0
      fi
    else
      if [ -f "$errfile" ] && grep -qF "$(cat "$errfile")" "$tmp/cws_$name.log"; then
        ok=1
      else
        echo "FAIL ws-case $name (unexpected failure)"
        sed 's/^/    /' "$tmp/cws_$name.log"
        ok=0
      fi
    fi
    if [ "$ok" = 1 ]; then
      echo "PASS ws-case $name"
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
    fi
  done
fi

# WebSharper.UI apps (A'' pipeline via build-ui-app.sh).
apps_ui="$here/apps-ui"
if [ -d "$apps_ui" ] && command -v ocamlfind > /dev/null 2>&1 && ocamlfind query websharper-ui > /dev/null 2>&1; then
  for ml in "$apps_ui"/*.ml; do
    [ -f "$ml" ] || continue
    aname="$(basename "$ml" .ml)"
    aout="$tmp/ui_$aname"
    mkdir -p "$aout"
    if ! bash "$here/../../scripts/build-ui-app.sh" "$ml" "$aout" > "$tmp/ui_$aname.build" 2>&1; then
      echo "FAIL ui $aname (build)"
      sed 's/^/    /' "$tmp/ui_$aname.build"
      fail=$((fail + 1))
      continue
    fi
    if [ -f "$apps_ui/$aname.mjs" ]; then
      node "$apps_ui/$aname.mjs" "$aout" > "$tmp/ui_$aname.actual" 2>&1 || true
    else
      node "$aout/Main.js" > "$tmp/ui_$aname.actual" 2>&1 || true
    fi
    expectedOut="$apps_ui/$aname.out"
    if [ "$update" = 1 ]; then
      cp "$tmp/ui_$aname.actual" "$expectedOut"
      echo "updated ui_$aname.out"
    fi
    if [ -f "$expectedOut" ] && ! diff -u "$expectedOut" "$tmp/ui_$aname.actual" > "$tmp/ui_$aname.diff"; then
      echo "FAIL ui $aname (output mismatch)"
      sed 's/^/    /' "$tmp/ui_$aname.diff"
      fail=$((fail + 1))
      continue
    fi
    echo "PASS ui $aname"
    pass=$((pass + 1))
  done
fi

# Client/server RPC over HTTP: the same source builds a JS client and a native
# OCaml server (generated via --emit-server); the client calls it via fetch.
if command -v ocamlfind > /dev/null 2>&1 && ocamlfind query yojson > /dev/null 2>&1; then
  if bash "$wsroot/scripts/rpc-demo.sh" "$tmp/rpc-server" > "$tmp/rpc.actual" 2>&1; then
    expected="$here/rpc_server.out"
    if [ "$update" = 1 ]; then
      cp "$tmp/rpc.actual" "$expected"
      echo "updated rpc_server.out"
    fi
    if [ -f "$expected" ] && ! diff -u "$expected" "$tmp/rpc.actual" > "$tmp/rpc.diff"; then
      echo "FAIL rpc-server (output mismatch)"
      sed 's/^/    /' "$tmp/rpc.diff"
      fail=$((fail + 1))
    else
      echo "PASS rpc-server"
      pass=$((pass + 1))
    fi
  else
    echo "FAIL rpc-server (build/run)"
    sed 's/^/    /' "$tmp/rpc.actual"
    fail=$((fail + 1))
  fi
else
  echo "SKIP rpc-server (ocamlfind/yojson not available)"
fi

# Structured [@rpc] values (records/variants/tuples/lists/options) round-trip
# through the native server's generated codecs.
if command -v ocamlfind > /dev/null 2>&1 && ocamlfind query yojson > /dev/null 2>&1; then
  if bash "$wsroot/scripts/rpc-data.sh" "$tmp/rpc-data" > "$tmp/rpcdata.actual" 2>&1; then
    expected="$here/rpc_data.out"
    if [ "$update" = 1 ]; then
      cp "$tmp/rpcdata.actual" "$expected"
      echo "updated rpc_data.out"
    fi
    if [ -f "$expected" ] && ! diff -u "$expected" "$tmp/rpcdata.actual" > "$tmp/rpcdata.diff"; then
      echo "FAIL rpc-data (output mismatch)"
      sed 's/^/    /' "$tmp/rpcdata.diff"
      fail=$((fail + 1))
    else
      echo "PASS rpc-data"
      pass=$((pass + 1))
    fi
  else
    echo "FAIL rpc-data (build/run)"
    sed 's/^/    /' "$tmp/rpcdata.actual"
    fail=$((fail + 1))
  fi
else
  echo "SKIP rpc-data (ocamlfind/yojson not available)"
fi

# Server-side rendering + client hydration (native server renders HTML; the
# client bundle hydrates the [@client] region in jsdom).
if command -v ocamlfind > /dev/null 2>&1 && ocamlfind query yojson > /dev/null 2>&1 \
   && ocamlfind query websharper-ui > /dev/null 2>&1; then
  if bash "$wsroot/scripts/ssr-demo.sh" "$tmp/ssr" > "$tmp/ssr.actual" 2>&1; then
    expected="$here/ssr.out"
    if [ "$update" = 1 ]; then cp "$tmp/ssr.actual" "$expected"; echo "updated ssr.out"; fi
    if [ -f "$expected" ] && ! diff -u "$expected" "$tmp/ssr.actual" > "$tmp/ssr.diff"; then
      echo "FAIL ssr (output mismatch)"
      sed 's/^/    /' "$tmp/ssr.diff"
      fail=$((fail + 1))
    else
      echo "PASS ssr"
      pass=$((pass + 1))
    fi
  else
    echo "FAIL ssr (build/run)"
    sed 's/^/    /' "$tmp/ssr.actual"
    fail=$((fail + 1))
  fi
else
  echo "SKIP ssr (ocamlfind/yojson/websharper-ui not available)"
fi

# M5: [@website] sitelet -> server-rendered pages (+ injected scripts), RPC, static assets.
if command -v ocamlfind > /dev/null 2>&1 && ocamlfind query yojson > /dev/null 2>&1 \
   && ocamlfind query websharper-ui > /dev/null 2>&1; then
  if bash "$wsroot/scripts/site-demo.sh" "$tmp/site" > "$tmp/site.actual" 2>&1; then
    expected="$here/site.out"
    if [ "$update" = 1 ]; then cp "$tmp/site.actual" "$expected"; echo "updated site.out"; fi
    if [ -f "$expected" ] && ! diff -u "$expected" "$tmp/site.actual" > "$tmp/site.diff"; then
      echo "FAIL site (output mismatch)"; sed 's/^/    /' "$tmp/site.diff"; fail=$((fail + 1))
    else echo "PASS site"; pass=$((pass + 1)); fi
  else
    echo "FAIL site (build/run)"; sed 's/^/    /' "$tmp/site.actual"; fail=$((fail + 1))
  fi
else
  echo "SKIP site (ocamlfind/yojson/websharper-ui not available)"
fi

# Templates: generator goldens + native SSR render of the generated module.
tplgen="$here/../../frontend/_build/default/bin/template_gen.exe"
tpl="$here/template"
if [ -x "$tplgen" ]; then
  tout="$tmp/template"; mkdir -p "$tout"
  if "$tplgen" --server "$tpl/card.html" "$tout" Card_tpl > "$tmp/tpl.gen.log" 2>&1; then
    if [ "$update" = 1 ]; then
      cp "$tout/Card_tpl.mli" "$tpl/card_tpl.mli.expected"
      cp "$tout/Card_tpl.ml" "$tpl/card_tpl.ml.expected"
      echo "updated template codegen goldens"
    fi
    ok=1
    if ! diff -u "$tpl/card_tpl.mli.expected" "$tout/Card_tpl.mli" > "$tmp/tpl.mli.diff"; then
      echo "FAIL template (codegen .mli)"; sed 's/^/    /' "$tmp/tpl.mli.diff"; ok=0
    fi
    if ! diff -u "$tpl/card_tpl.ml.expected" "$tout/Card_tpl.ml" > "$tmp/tpl.ml.diff"; then
      echo "FAIL template (codegen .ml)"; sed 's/^/    /' "$tmp/tpl.ml.diff"; ok=0
    fi
    if [ "$ok" = 1 ] && command -v ocamlfind > /dev/null 2>&1 \
       && ocamlfind query websharper-ui-server > /dev/null 2>&1; then
      cp "$tpl/driver.ml" "$tout/"
      if (cd "$tout" && ocamlfind ocamlopt -package websharper-ui-server -linkpkg \
            Card_tpl.mli Card_tpl.ml driver.ml -o render) > "$tmp/tpl.build" 2>&1; then
        "$tout/render" > "$tmp/tpl.actual" 2>&1
        if [ "$update" = 1 ]; then cp "$tmp/tpl.actual" "$tpl/expected.out"; echo "updated template expected.out"; fi
        if ! diff -u "$tpl/expected.out" "$tmp/tpl.actual" > "$tmp/tpl.out.diff"; then
          echo "FAIL template (render)"; sed 's/^/    /' "$tmp/tpl.out.diff"; ok=0
        fi
      else
        echo "FAIL template (build)"; sed 's/^/    /' "$tmp/tpl.build"; ok=0
      fi
    fi
    if [ "$ok" = 1 ]; then echo "PASS template"; pass=$((pass + 1)); else fail=$((fail + 1)); fi
  else
    echo "FAIL template (generator)"; sed 's/^/    /' "$tmp/tpl.gen.log"; fail=$((fail + 1))
  fi
else
  echo "SKIP template (frontend not built)"
fi

# Frontend diagnostics: each fixture must fail with the expected located error,
# normalized by `diag.exe` to `file:line:col:col: severity: message` (the fixture
# directory is stripped so the goldens are portable).
errs="$here/errors"
fe="$wsroot/frontend/_build/default/bin/main.exe"
diagexe="$wsroot/frontend/_build/default/bin/diag.exe"
if [ -d "$errs" ] && [ -x "$fe" ] && [ -x "$diagexe" ] \
   && command -v ocamlfind > /dev/null 2>&1 \
   && ocamlfind query websharper-ui > /dev/null 2>&1; then
  e_ui="$(ocamlfind query websharper-ui)"
  e_jsl="$(ocamlfind query websharper-javascript)"
  e_rt="$(ocamlfind query websharper-runtime)"
  e_sl="$(ocamlfind query websharper-stdlib)"
  for ml in "$errs"/*.ml; do
    [ -f "$ml" ] || continue
    name="$(basename "$ml" .ml)"
    # The frontend is expected to fail; the diagnostic stream is what we compare.
    "$fe" --input "$ml" --output "$tmp/$name.wsir.json" --emit-server "$tmp/$name.server.ml" \
      --unit Main -I "$e_ui" -I "$e_jsl" -I "$e_rt" -I "$e_sl" -I "$(ocamlc -where)" 2>&1 \
      | "$diagexe" | sed "s|^$errs/||" > "$tmp/$name.err" || true
    expected="$errs/$name.err"
    if [ "$update" = 1 ]; then cp "$tmp/$name.err" "$expected"; echo "updated $name.err"; fi
    if [ ! -s "$tmp/$name.err" ]; then
      echo "FAIL error $name (no diagnostic)"; fail=$((fail + 1)); continue
    fi
    if [ ! -f "$expected" ]; then
      echo "FAIL error $name (missing $(basename "$expected"); run with --update)"
      fail=$((fail + 1)); continue
    fi
    if ! diff -u "$expected" "$tmp/$name.err" > "$tmp/$name.err.diff"; then
      echo "FAIL error $name (diagnostic mismatch)"
      sed 's/^/    /' "$tmp/$name.err.diff"
      fail=$((fail + 1)); continue
    fi
    echo "PASS error $name"; pass=$((pass + 1))
  done
else
  echo "SKIP errors (frontend/ocamlfind not available)"
fi

# Diagnostic normalization (`diag.exe`): an exception *message* must survive
# even when it ends in `)`; only the redundant `Printexc.to_string` line that
# follows a formatted report (`Typecore.Error(_, _, _)`, `Location.Error(_)`)
# is dropped.
if [ -x "$diagexe" ]; then
  msg='System.Exception: WebSharper_Json.encode/decode must be called directly (the call-site type is needed)'
  printf '%s\n%s\n%s\n' "$msg" 'Location.Error(_)' 'Unhandled exception. System.Exception: boom (context)' \
    | "$diagexe" > "$tmp/diag.actual" 2>&1
  printf '%s\n%s\n' "$msg" 'Unhandled exception. System.Exception: boom (context)' > "$tmp/diag.expected"
  if diff -u "$tmp/diag.expected" "$tmp/diag.actual" > "$tmp/diag.diff"; then
    echo "PASS diag"; pass=$((pass + 1))
  else
    echo "FAIL diag (normalization)"; sed 's/^/    /' "$tmp/diag.diff"; fail=$((fail + 1))
  fi
else
  echo "SKIP diag ($diagexe not built)"
fi

echo
echo "passed: $pass, failed: $fail"
[ "$fail" = 0 ]