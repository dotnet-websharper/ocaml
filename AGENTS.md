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
| diag normalization | inline in `run-tests.sh` (an exception message ending in `)` must survive) | — |
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
| `bindings/**` (opam packages of WebSharper bindings) | `dotnet binding-adaptor/bin/Debug/net10.0/binding-adaptor.dll gen <Binding.dll> --version <v> --dest ./bindings` (the ordered, exact command set is in `README.md`); `specs/*.spec` control the generated module names/merges, and are applied for the package **and for every `--reference`**, so a spec must exist before regenerating its dependents. `websharper-ui` **must** be generated with `--reference WebSharper.Sitelets.dll` (else `WebSharper.UI.Router`'s `Router<'T>` argument mis-binds to `Router.t`); `specs/websharper-stdlib.spec` and `specs/websharper-sitelets.spec` repair the module-name collisions the flat naming cannot decide (`System.DateTime` -> `DateTime`, `<Type>Module` helpers, `Nullable`/`NullableHelpers`, the `*Enumerator`s, `InferRouter`) |
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
| `frontend/bin/main.ml` | the compiler: parse → `transformTemplates` → `transformInfer` → `transformClientServer` → `transformClientEvents` → `transformJson` → `checkBoundary` → typecheck → emit IR or `server.ml` (`jsonCalls` reads typed-JSON call sites off the typedtree) |
| `frontend/bin/diag.ml` | rewrites multi-line compiler reports to `file:line:startCol:endCol: severity: message` for the editor problem matcher |
| `backend/` | F#: `Ir.fs` reads the IR, `Lowering.fs` lowers to WebSharper AST, `Program.fs` bundles/validates, `Runtime.js` is an embedded resource |
| `runtimes/server-api/*.mli` | client-facing stubs of the server API (frontend typechecks app source against these) |
| `runtimes/server-api/webSharper_Json.ml` | typed-JSON stub (`WebSharper_Json.encode`/`decode`); a `.ml` on purpose, so its `wsocaml:json_*` primitives survive into the `.cmi` |
| `runtimes/ocaml/*.ml` | native implementations: `ssr.ml` (HTML nodes/regions), `wsrpc.ml` (JSON-RPC server), `webSharper_Server.ml`, `webSharper_ClientServer.ml`, `webSharper_Json.ml` (native shadow of the client-only typed JSON), `async.ml` |
| `runtimes/ocaml/*.mjs` | the node drivers the demos use (`site_client.mjs` needs jsdom) |
| `runtimes/ui-server/webSharper_UI.ml` | native SSR shadow of WebSharper.UI (`Doc`/`View`/`Var`/`Attr`/`Router`/`ListModel` + the `Template` engine), same module name as the client binding |
| `runtimes/ui-server/webSharper_Sitelets.ml` | native shadow of the `WebSharper.Sitelets` hash router (`Router` = `Router<'T>`, `RouterMatcher`, `RouterModule`, `Route`) that `WebSharper.UI.Router.installHash` takes; the server never hashes |
| `runtimes/template/` | `websharper-template`: HTML parser + hole model + `Codegen` for `[%template]` |
| `binding-adaptor/` | F# tool: binding assembly → OCaml opam package |
| `specs/*.spec` | binding-adaptor input controlling generated package/module shape: `websharper-stdlib.spec` (the collision repairs listed in `README.md`: `System.DateTime` -> `DateTime`, `WebSharper.JavaScript.Pervasives+DateTime` -> `DateTimeFormat`, `<Type>Module` helpers, `Nullable`/`Optional` vs their helpers, `JavaScriptPervasives`, `LinqEnumerable`, the `*Enumerator`s), `websharper-sitelets.spec` (``WebSharper.Sitelets.Router`1`` -> `Router` + `RouterMatcher`, `InferRouter+Router` -> `InferRouter`) and `websharper-ui.spec` (merges + `Html`/`On` names) |
| `scripts/*.sh` | per-scenario drivers (see "What the suite covers") |
| `backend/tests/apps-site/`, `apps-ui/`, `apps-ws/`, `apps/`, `cases/`, `cases-ws/`, `errors/`, `template/` | the harness families |
| `examples/` | dune projects type-checked against the installed bindings; `hello-world` is the end-to-end reference app, `todomvc` (client-rendered) / `todomvc-full` (SSR + `bind` + hash router) / `todomvc-lm` (`ListModel` state) are the WebSharper.UI ones |

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
4. **`diag.exe` drops the redundant `X.Y(...)` line** the driver prints after a
   formatted report (`Printexc.to_string exn`, e.g. `Typecore.Error(_, _, _)`,
   `Location.Error(_)`; see `is_exception` in `frontend/bin/diag.ml`). It only
   drops it when the line has **no colon**, so exception *messages* such as
   `System.Exception: … (…)`, `Unhandled exception. …`, and
   `Fatal error: exception …` still reach the terminal. Do not widen this to
   "anything ending in `)`" — that swallowed the only useful line of backend
   crashes whose message ends with `)` (and there is a `diag` regression test in
   `backend/tests/run-tests.sh`).
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
    `WebSharper.UI.Router` cmi names `WebSharper_Sitelets.Router.t`) and
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
15. **Binding module names are collision-suffixed.** binding-adaptor derives a
    module name from a class's JS address (last segment) or its .NET simple name
    (`Generator.classModuleName`), groups colliding names, sorts prototype-bearing
    (`default`-export) classes first — they keep the bare name — and suffixes the
    rest `2`, `3`, …; a group merges instead only when exactly one member is the
    max-arity type and the others are static helpers (`Var<'T>` + `Var`). When
    *both* members are module-root the tie-break is metadata order — that is where
    `DateTime2`, `Nullable2` and `Router2` came from; fix such pairs with a `spec`
    rename (`specs/websharper-stdlib.spec` / `websharper-sitelets.spec` — the full
    list is in `README.md`). Distinguish a collision (different .NET types that
    merely share a derived module name — positional `2`, `3`, …, as today; JS
    globals like `Object`/`Array`/`Console` are pinned) from a **generic family**
    (the *same* .NET type name at different arities), which is named by arity
    with an `Of` suffix by `Program.fs` `finalNamesFor`: `<Name>Of` for one type
    parameter, `<Name><n>Of` for n >= 2 (`TaskOf<'T>`, `IEnumerableOf<'T>`,
    `TupleOf<'T1>`, `Tuple2Of<'T1,'T2>`, `Union2Of`, `FSharpFunc2Of`,
    `ThisFunc2Of`, `ParamsFunc2Of`, …). The arity is read from the metadata name
    (`arityOf`), not the class's generic count — cyclic interfaces such as
    `IComparable<'T>`/`IDictionary<'K,'V>` are collapsed to `type t`.
    Note the fix usually has *two* entries (the generic/useful member takes the
    bare name), and after renaming check the regenerated file list for fresh
    `*2` files: `EventModule` silently collided with F#'s own
    `Microsoft.FSharp.Control.EventModule`. A spec is
    applied for the package **and for each `--reference`**, so add it before
    regenerating dependents. Regenerating can also surface unrelated generator
    drift (e.g. `event.ml` gaining a `%identity` upcast) — review the diff, and
    note that an upcast to a base in another package must be qualified via
    `TypeEnv.ExternalSimple`.

16. **Typed JSON is call-site-indexed and client-only.** `WebSharper_Json.encode
    e` / `decode s` become `__encode <i> e` / `__decode <i> s` in `transformJson`;
    after typechecking `jsonCalls` reads the instantiated type at that node and
    the IR's `json` section maps `<i>` to a `descr` descriptor, which
    `Lowering.prim` inlines as `OCamlRuntime.jsonEncode/Decode`. The bare
    `encode`/`decode` spelling is only rewritten when the unit has
    `open WebSharper_Json` (so a user-defined `encode` is not hijacked).
    Consequences: the stub must stay a `.ml` (an `.mli` drops the
    `wsocaml:json_*` primitive and the call turns into a plain global), the
    value's type must be concrete at the call site (annotate polymorphic
    callers), and the descriptor shares the unit's `types` table, so
    `registerTypes` must run before a `named` decode. A use the rewrite cannot
    see (an alias, `List.map WebSharper_Json.encode …`) is a located diagnostic
    in `jsonCalls`; a type it cannot describe (e.g. `state Var.t`, or a type
    variable) is a located `cannot marshal a value of type … to typed JSON`.
    There is no native implementation: `let () =` bodies (where this is normally
    used) are dropped from `server.ml`.

17. **Binding `open`s shadow, and the editor typechecks against the *shadows*
    while the build uses the generated bindings.** `open WebSharper_UI` (client
    binding)
    re-exports `Storage`, `Array`, `Attr`, `Notation`, hiding the same-named
    `WebSharper_JavaScript` modules — the DOM side needs qualifying or an alias
    (`module JsStorage = WebSharper_JavaScript.Storage`). `WebSharper_JavaScript`
    in turn shadows stdlib modules (`String`, `Array`, `Object`, …), hence
    `module String = Stdlib.String` in the examples. And because
    `examples/*/dune` lists `websharper-ui-server` (the 19-submodule native
    shadow) while `build.sh`/the suite list the generated `websharper-ui` (80),
    a bare `Storage`/`Array` can typecheck in the editor and fail in the build, or
    the reverse — `dune build` under `examples/` is an editor convenience only.
    README → *Name collisions and shadowing*.

18. **`bool` is `0`/`1` at runtime; keep it that way.** Source literals,
    `marshalIn`, and the `caml_*` helpers all use `0`/`1`, so the inline
    bool-producing prims must too: `not` lowers to `a ? 0 : 1` and the
    comparisons to `(... ? 1 : 0)` (`Lowering.boolVal`). A JS `false`
    (from a bare `!` or a JS comparison) is a different value: it is not
    `=== 0`, so bool equality breaks, and `caml_compare`/`marshalOut` mis-handle
    it — `marshalOut` used to send it as `true`, which is how a toggled TodoMVC
    checkbox failed to survive a reload. `marshalOut`'s `bool` case is `!!v` so
    a real JS boolean *from JS interop* still marshals correctly.

19. **A bare top-level module *alias* takes no module-block slot.**
    `module M = Other` (typedtree `Tstr_module` with `Tmod_ident`) shares the
    aliased module's field, so `Translmod` does not grow the block — but
    `topIndex` used to `incr` for every `Tstr_module`, shifting the
    `[@rpc]`/`[@client]`/`[@export]` indices by one and misbinding the hydrated
    region (a runtime `TypeError`, not a build error). Only bare `Tmod_ident` is
    skipped: `module M = struct … end` and a constrained alias
    (`module M = (Other : S)`) do take a slot. `apps-site` has such an alias as a
    regression test. Relatedly, `--emit-server`'s `typecheckServer` now *prepends*
    the native include dirs to the client ones (it used to replace them), so
    shared source may name a client-only package's modules (e.g.
    `WebSharper_StdLib`) from a top-level item that survives into `server.ml`.

20. **`IEnumerable<'T>` is OCaml `Seq.t`, converted at the boundary.**
    `Generator.isEnumerableFullName` makes `mapType` present an `IEnumerable<'T>`
    *result* as `'T Seq.t` (and `paramType` too, for a type whose spec sets
    `seqParams`, e.g. F# `Seq`/`List`/`LinqEnumerable` — those parameters also
    carry a `@seq` marker in the `ws:` prim string that `Lowering` strips for the
    metadata lookup and uses to pick `caml_seq_to_js`). A WebSharper
    `IEnumerable` is a `{ GetEnumerator() }` object and an OCaml `Seq.t` is
    `unit -> node`, so the conversions (`js_to_caml_seq` / `caml_seq_to_js`, plus
    `caml_to_js_seq` for `fn` arrows) are in `backend/Runtime.js` and are
    *eager*. `IEnumerable` inside a `fn` position whose type is a *type variable*
    (`Doc.bindView`'s `'a -> Doc`) cannot be converted from the metadata alone —
    that is why the `Seq`/`List` shims accept either representation.

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
