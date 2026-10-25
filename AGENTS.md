# AGENTS.md

Working notes for `wsocaml` (OCaml → WebSharper compiler). One source file is
compiled two ways: a **JS client bundle** (frontend → `.wsir.json` IR → F#
backend → WebSharper JS) and a **native OCaml server** (frontend
`--emit-server` → `server.ml` → `ocamlfind`/`ocamlopt`). Design docs live in
`docs/` — see the docs map below for which one to update.

## Prerequisites

- OCaml 5.4.x via opam (`eval "$(opam env)"`), dune; local bindings installed:
  `opam repo add wsocaml ./bindings && opam install websharper-javascript websharper-sitelets websharper-ui websharper-runtime websharper-stdlib`,
  and the native shadows with `opam install ./runtimes/ocaml ./runtimes/ui-server`.
  `websharper-ui` depends on `websharper-sitelets` (`WebSharper.UI.Router` refers
  to `WebSharper.Sitelets.Router<'T>`). `frontend/dune-project` pins
  `ocaml (= 5.4.1)`.
- .NET SDK 10 (`backend/` targets `net10.0`), Node, and `npm install` at the repo
  root (that is where `jsdom` comes from — the `site`/`ssr` drivers need it).
- `ocamlfind` + the packages above for the native server tests
  (`websharper-server`, `websharper-ui-server`, `yojson`, `websharper-template`).
- `LICENSE.md` carries an unrelated local modification (copyright wording):
  **never commit it** (`git reset -q LICENSE.md` before staging).

## Build

```sh
cd frontend && eval "$(opam env)" && dune build   # bin/{main,diag,template_gen,required_globals}.exe
cd backend  && dotnet build                       # bin/Debug/net10.0/WebSharper.OCaml.dll
```

- `bash build.sh` does both (frontend + backend **Release**), but the test suite
  drives the **Debug** DLL (`backend/bin/Debug/net10.0/WebSharper.OCaml.dll`),
  so build the backend without `-c Release` before testing.
- `dotnet build` must run **inside `backend/`** — there is no solution file at the
  repo root.
- `frontend/bin/main.exe` links `compiler-libs.common`, `yojson` and
  `websharper-template`; the other executables are one-off generators (see
  "Regenerating generated things").

## Test

```sh
bash scripts/test-quick.sh                  # kitchensink app only: the fast inner loop
bash backend/tests/run-tests.sh             # full suite (builds the backend first)
bash backend/tests/run-tests.sh --no-build  # skip the backend build
bash backend/tests/run-tests.sh --update    # refresh *.expected.js / *.out / *.err goldens
```

- **`SKIP` means unverified, not passing.** Whole families skip when the frontend
  has not been `dune build`-ed or `ocamlfind`/node/jsdom are missing, so a green
  run can be missing coverage. Grep the output for `SKIP` after changing the
  frontend or the environment.
- Per-scenario demos build, serve and drive a single app on port 8123; they fail
  fast if the port is taken (`lsof -ti tcp:8123 | xargs kill`):
  `site-demo.sh <out>` (sitelet; the entry is hardcoded to
  `backend/tests/apps-site/wssite.ml`), `ssr-demo.sh <out>`, `rpc-demo.sh`,
  `rpc-data.sh`.

### What the suite covers

| Family | How it runs | Golden |
| --- | --- | --- |
| `cases/*.wsir.json` | backend only — committed IR fixtures (there is no `.ml` for them in the repo, and nothing regenerates them) | `<name>.expected.js`, optional `<name>.driver.mjs` + `<name>.out` |
| `cases/<dir>/` | backend, several units | per-unit `.wsir.json` + `main.mjs` + `expected.out` |
| `cases-ws/*.wsir.json` | backend with `--reference WebSharper.StdLib.dll` | `<name>.expected.js`, or `<name>.expected.err` when the compile is expected to fail |
| `apps/*.ml` | frontend → backend (`build-js-app.sh`) | `<name>.out` (+ `<name>.mjs` driver) |
| `apps-ws/*.ml` | `build-ws-app.sh` | `<name>.out` (+ `<name>.dts` golden for `[@export]`) |
| `apps-ui/*.ml` | `build-ui-app.sh` | `<name>.out` (+ `<name>.mjs` driver) |
| `apps-site/wssite.ml` | `site-demo.sh` end to end (native server) | `site.out` |
| `errors/*.ml` | frontend + `diag.exe` (must fail) | `<name>.err` |
| `template/` | `template_gen.exe` goldens + a native render of `card_tpl` | `card_tpl.ml/.mli.expected`, `expected.out` |
| rpc / ssr | `rpc-demo.sh`, `rpc-data.sh`, `ssr-demo.sh` | `rpc_server.out`, `rpc_data.out`, `ssr.out` |

## Frontend CLI (hand-debugging)

```sh
fe=frontend/_build/default/bin/main.exe
# client IR
$fe --input app.ml --output app.wsir.json --unit Main -I <include dirs…>
# native server
$fe --input app.ml --emit-server server.ml --unit Main --static <client dir> \
    [--server-include <dir> …] -I <include dirs…>
```

- `-I` needs: `ocamlfind query websharper-ui websharper-javascript websharper-runtime websharper-stdlib`,
  the compiled client-facing stubs from `runtimes/server-api/*.mli`, and
  `$(ocamlc -where)`. `scripts/site-demo.sh` shows the full incantation;
  `examples/hello-world/build.sh` adds the `--server-include` set used for the
  native typecheck.
- `--preprocess` prints the source after `[%template]` expansion (no typecheck);
  `--dts <path>` writes TypeScript declarations for `[@export]`;
  `--template-root <dir>` rebases `[%template]` paths.
- Pipe output through `frontend/_build/default/bin/diag.exe` to get
  `file:line:startCol:endCol: severity: message` (the same normalization the
  editor problem matcher uses via `examples/hello-world/check.sh`).

## Backend CLI

```sh
dotnet backend/bin/Debug/net10.0/WebSharper.OCaml.dll --ir app.wsir.json \
  --output <dir> --compact [--reference WebSharper.UI.dll …] [--ws-compile …]
```

- `--reference` supplies the assemblies whose WebSharper metadata the `ws:`
  externals in the bindings resolve against (binding apps pass
  `WebSharper.UI.dll`, `WebSharper.StdLib.dll`, `WebSharper.JavaScript.dll`);
  `--ws-compile` runs the WebSharper packager/bundler instead of plain emission.
- The IR is the *only* contract between the OCaml frontend and the F# backend.
  `Program.fs` validates `schema` (`wsocaml-ir-6`, with `wsocaml-ir-5`/`4` still
  accepted), so a shape change means bumping the string in `frontend/bin/main.ml`
  **and** the check in `Program.fs`.
- `types` (unit-level, `wsocaml-ir-6`) holds the named record/variant
  declarations keyed by a stable id; per-rpc/export metas reference them by id and
  the backend emits `OCamlRuntime.registerTypes([…])` once (`Lowering.typeRegs`).
  Additive: `ir-4`/`5` descriptors keep their own `types`/`key` refs, so the
  committed `cases/*.wsir.json` fixtures still compile (see `JSON.md` §5).

## Regenerating generated things (never hand-edit these)

| Artifact | Regenerate with |
| --- | --- |
| `bindings/**` (opam packages of WebSharper bindings) | `dotnet binding-adaptor/bin/Debug/net10.0/binding-adaptor.dll gen <Binding.dll> --version <v> --dest ./bindings` (exact lines in `README.md`); `specs/*.spec` control the generated module names/merges. `websharper-ui` **must** be generated with `--reference WebSharper.Sitelets.dll` (else `WebSharper.UI.Router`'s `Router<'T>` argument mis-binds to `Router.t`) |
| `bindings-legacy/**` | raw-FFI fixture for the `jsbind`/`dom` tests (`frontend/bin/gen_bindings.ml`) |
| `frontend/bin/stdlib_shims_data.ml` | `frontend/bin/gen_stdlib_shim.ml` |
| all test goldens (`*.expected.js`, `*.out`, `*.err`, `*.expected`) | `bash backend/tests/run-tests.sh --update` |
| every emitted JS bundle | `backend/Runtime.js` is embedded as a resource by `Program.fs` — see gotcha 1 |

## Docs map

| Doc | Covers | Update it when |
| --- | --- | --- |
| `docs/client-server.md` | tier split, hydration/SSR, server-rendered event handlers (§4.1), sitelets (§7), endpoint status (§7.2), deferred work (§6), the RPC external representation (§3.2) | boundary, hydration or sitelet semantics change |
| `JSON.md` (repo root) | the RPC/`[@export]` marshalling long form: why it is hand-rolled rather than WebSharper's built-in JSON, what WS's JSON machinery actually is (`System.Type` reflection, `CustomTypeInfo`, `JsonSerializerEntry`), the runtime-representation delta, what adopting it would take, alternatives | the wire format, the `Runtime.js` marshaller, the IR descriptors, or a decision on the WS-JSON roadmap changes |
| `docs/hydrate-client.md` | `hydrate`/`client` regions end to end: the compiler lift + IR `clients`, client `registerClient`, `server.ml` selection and bootstrap, served HTML, the `Runtime.js` lifecycle, invariants | region/hydration implementation, `Runtime.js`, or emitted-marker changes |
| `docs/client-bundle.md` | the client JS output: file layout, the per-class WebSharper ESM modules the packager emits, how relative imports resolve, static serving, the runtime prelude, why no bundler, external JS libraries (§11: globals vs `[<Import>]`) | JS emission/`--ws-compile`/packaging, how the bundle is served, or external-lib/resource handling |
| `docs/routing.md` | `[@endpoint]` semantics with verified snippets (§1–§11), diagnostics (§12), client-side hash routing / `Router.installHash` (§13), not-implemented list (§14) | endpoint semantics change (its snippets are copied from a real `--emit-server` run) |
| `docs/codegen.md` | what lands in `server.ml`, selection rules, diagnostics plumbing; cites `main.ml:<line>` | `emitServer`/printing changes — and refresh those line numbers |
| `docs/templates.md` | `[%template]` surface and hole types; deferred items (anchors, cross-file templates) | template codegen changes |
| `docs/ws-differences.md` | intentional differences from .NET WebSharper | a behaviour intentionally diverges |
| `README.md` | the public tour (build/test commands, bindings usage) | user-visible workflow changes |

## Where things live

| Path | What it is |
| --- | --- |
| `frontend/bin/main.ml` | the compiler: parse → `transformTemplates` → `transformInfer` → `transformClientServer` → `transformClientEvents` → `checkBoundary` → typecheck → emit IR or `server.ml` |
| `frontend/bin/diag.ml` | rewrites multi-line compiler reports to `file:line:startCol:endCol: severity: message` for the editor problem matcher |
| `backend/` | F#: `Ir.fs` reads the IR, `Lowering.fs` lowers to WebSharper AST, `Program.fs` bundles/validates, `Runtime.js` is an embedded resource |
| `runtimes/server-api/*.mli` | client-facing stubs of the server API (frontend typechecks app source against these) |
| `runtimes/ocaml/*.ml` | native implementations: `ssr.ml` (HTML nodes/regions), `wsrpc.ml` (JSON-RPC server), `webSharper_Server.ml`, `webSharper_ClientServer.ml`, `async.ml` |
| `runtimes/ocaml/*.mjs` | the node drivers the demos use (`site_client.mjs` needs jsdom) |
| `runtimes/ui-server/webSharper_UI.ml` | native SSR shadow of WebSharper.UI (`Doc`/`View`/`Var`/`Attr`/`Router` + the `Template` engine), same module name as the client binding |
| `runtimes/ui-server/webSharper_Sitelets.ml` | native shadow of the `WebSharper.Sitelets` hash router (`Router`/`Router2`/`RouterModule`/`Route`) that `WebSharper.UI.Router.installHash` takes; the server never hashes |
| `runtimes/template/` | `websharper-template`: HTML parser + hole model + `Codegen` for `[%template]` |
| `binding-adaptor/` | F# tool: binding assembly → OCaml opam package |
| `specs/*.spec` | binding-adaptor input controlling generated package/module shape |
| `scripts/*.sh` | per-scenario drivers (see "What the suite covers") |
| `backend/tests/apps-site/`, `apps-ui/`, `apps-ws/`, `apps/`, `cases/`, `cases-ws/`, `errors/`, `template/` | the harness families |
| `examples/` | dune projects type-checked against the installed bindings; `examples/hello-world` is the end-to-end reference app |

## Gotchas

1. **`Runtime.js` is embedded in every JS output.** Editing it invalidates all
   `backend/tests/cases/*.expected.js`; regenerate and check the diff is only the
   prelude.
2. **`scripts/build-ui-app.sh <entry> <out>` FE-compiles every sibling `*.ml`**
   next to the entry (that is how all of `backend/tests/apps-ui/*.ml` get built).
   A broken sibling fails the app build.
3. **Raise diagnostics as `Location.Error`** (`Location.raise_errorf ~loc`).
   In OCaml 5.4 `Location.report_exception` *re-raises* anything that is not a
   `Location.Error`, so the driver's handler never runs and you get a bare
   `Fatal error: exception …` with no file/line. `genRoute`'s old `Option.get`
   crash was exactly that; `endpointOf`/`endpointPlan`/`checkBoundary`/
   `transformClientEvents` now raise located errors — keep it that way.
4. **`diag.exe` drops `X.Y(...)`-shaped lines** (see `is_exception` in
   `frontend/bin/diag.ml`), which is why the driver also printing
   `Printexc.to_string exn` does not pollute the matcher output.
5. **OCaml 5.4 parsetree:** `Pexp_fun` no longer exists — functions are
   `Pexp_function (function_param list, type_constraint option, function_body)`
   with `function_param = { pparam_desc; pparam_loc }`. `Ast_mapper` exposes
   `case`/`cases` but has **no** `function_param`/`function_body` hooks, so those
   are walked by hand. `Parsetree.case` has exactly three fields, so
   `{ c with … }` trips warning 23 (build them as records).
6. **`docs/*.md` cite `main.ml:<line>`** (`codegen.md` especially). Any edit to
   `frontend/bin/main.ml` shifts them — refresh with
   `rg -n 'main\.ml:[0-9]+' docs/`.
7. **Errors-harness goldens** (`backend/tests/errors/*.err`) are `diag.exe`
   output with the fixture directory stripped; a fixture without a golden is a
   FAIL, so add new ones with `run-tests.sh --update`.
8. **The `emitServer` filter is `js minus clients`**: `[@javascript]` and
   `[@export]` values are dropped from `server.ml`, `[@client]` values are kept
   (they are server-rendered). Anything new that the server references but must
   not link natively (like a lifted event handler) has to be `[@javascript]` so
   it lands in that dropped set.
9. **Client event names are camelCase** in the client binding
   (`bindings/…/on.ml`: `dblClick`, `keyDown`, `keyUp`) while source writes
   `on.dblclick`/`on.keydown`/`on.keyup`, which `transformClientServer` copies
   verbatim to `On.dblclick`/… — those do not resolve client-side today. Only
   `click`, `change`, `input`, `submit` line up. `clientEventNames` in
   `main.ml` lists the seven events the compiler understands; the server shadow
   `On` defines `click` only.
10. **`ws-on<event>` is shared with templates** (`runtimes/template/hole.ml`
    treats any `ws-on*` as an event hole); the runtime's `attachEvents` only wires
    values present in the `clientCode` store, so compiler markers and template
    holes do not collide.
11. **The demo scripts compile the shadows from source.** `scripts/site-demo.sh`
    / `ssr-demo.sh` `cp` `runtimes/ui-server/webSharper_UI.ml` and compile it with
    `ocamlfind` directly (not via dune), so `webSharper_Sitelets.ml` must be
    copied and listed **before** `webSharper_UI.ml` there too. `build-ui-app.sh`
    needs `-I $(ocamlfind query websharper-sitelets)` (the regenerated
    `WebSharper.UI.Router` cmi names `WebSharper_Sitelets.Router2.t`) and
    `--reference WebSharper.Sitelets.dll`.
12. **Event keys are content-derived**: `wsh<digits>` = `Hashtbl.hash` of the
    handler's `Pprintast` text, which is stable across processes — that is what
    makes the server's `ws-on<event>` marker and the client's
    `registerClient` agree. Any change to key derivation must keep the server and
    client builds producing identical keys; the site test locks this in.
13. **Generated routes are a `match` in declaration order.** Overlapping
    endpoints silently favour the first one, and the compiler reports
    `Warning 11 [redundant-case]` at the `Sitelet.infer` call site.
14. **`examples/hello-world/verify.mjs` is stale** (jsdom lacks a `Node` global,
    so the template runtime throws at import, and it asserts a `>before<` region
    the page does not have). `bash build.sh` plus `curl` is the reliable check;
    `hello_world.ml` uses `[@endpoint "GET /echo/@0"]` (tuple payloads are
    positional).

## Adding a feature

- Runtime/JS behaviour or sitelet/RPC coverage → extend
  `backend/tests/apps-site/wssite.ml` plus `runtimes/ocaml/site_client.mjs` and
  `backend/tests/site.out`.
- A compiler diagnostic → add `backend/tests/errors/<name>.ml` and its `.err`
  golden (`--update`).
- Client-side (UI) behaviour → `backend/tests/apps-ui/<name>.ml` (+ optional
  `<name>.mjs` driver and `<name>.out`).
- A plain-JS or binding-level lowering change → `backend/tests/cases*` (the IR
  fixtures are committed; run the frontend on a scratch `.ml` to produce one).
- Semantics changes: update the doc from the docs map, and keep `docs/routing.md`
  (and any other quoted snippets) in sync with a real run.
