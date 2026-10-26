# wsocaml — an OCaml frontend for WebSharper

`wsocaml` compiles OCaml to JavaScript through WebSharper's AST and runtime:

```
Parse -> Typemod.type_structure -> Translmod.transl_implementation -> Lambda.program
  -> wsocaml-ir-6 -> WebSharper AST -> JavaScript
```

OCaml itself handles typing and pattern-match compilation; the frontend serializes
Lambda into `wsocaml-ir-6`, and the backend lowers it to WebSharper AST and emits JS.

## Layout

| Path | Purpose |
| --- | --- |
| `frontend/` | OCaml (dune) frontend: `.ml` → `wsocaml-ir-6`; template codegen (`frontend/template/`) |
| `backend/` | F#/.NET backend: `.wsir.json` → `.js` (also handles WebSharper bindings) |
| `binding-adaptor/` | F# tool: WebSharper binding assembly → OCaml opam package |
| `bindings/` | local opam repository of generated bindings (`websharper-xxx`) |
| `bindings-legacy/` | raw-FFI test fixture (`frontend/bin/gen_bindings.ml`), used by the `jsbind`/`dom` emit tests |
| `runtimes/template/` | `websharper-template`: shared HTML parser + template hole model |
| `runtimes/ocaml/` | `websharper-server`: representation-agnostic sitelets, Content, SSR nodes, HTTP |
| `runtimes/ui-server/` | `websharper-ui-server`: the native `WebSharper_UI` shadow (converts to `Ssr.node`) + template engine |
| `examples/` | dune projects built on the generated bindings / `websharper-server` |
| `scripts/` | build/test helpers |
| `backend/tests/` | test harness (IR fixtures + apps) |
| `docs/` | design notes (`client-server.md`, `hydrate-client.md`, `client-bundle.md`, `codegen.md`, `routing.md`, `templates.md`, `ws-differences.md`) |
| `AGENTS.md` | build/test conventions, layout and the traps to know when changing the compiler |

## Build

Frontend (OCaml 5.4.1):

    cd frontend && opam install dune yojson && dune build

Backend and adaptor:

    dotnet build backend
    dotnet build binding-adaptor

## Using WebSharper bindings

Generate an OCaml opam package from a WebSharper binding assembly (the package id
defaults to `websharper-<name>`; use `--id` to override):

    dotnet binding-adaptor/bin/Debug/net10.0/binding-adaptor.dll gen \
      ~/.nuget/packages/websharper/10.1.6.677/lib/netstandard2.0/WebSharper.JavaScript.dll \
      --version 10.1.6 --dest ./bindings

Add the local repository and consume the package:

    opam repo add wsocaml ./bindings
    opam install websharper-javascript

Each generated OCaml module (e.g. `Console`, `Date`, `JSON`) declares `external`s
tagged with the WebSharper member address, e.g.
`external log_2 : 'a -> unit = "ws:WebSharper.JavaScript!globalThis.console#Log|'0"`.
The backend resolves these addresses against WebSharper metadata passed with
`--reference <assembly.dll>`, inlining inline bodies and emitting thin
static/instance/new access.

Generated packages reference other WebSharper packages with `--reference`; cross-
package types are emitted qualified and the opam/dune dependencies are generated
automatically. Regenerate the whole set in this order (a package's `--reference`
set mirrors the `depends:` of its `opam`):

    BIND=~/.nuget/packages/websharper/10.1.6.676/lib/netstandard2.0
    UI=~/.nuget/packages/websharper.ui/10.1.5.676/lib/netstandard2.0
    GEN="dotnet binding-adaptor/bin/Debug/net10.0/binding-adaptor.dll gen"

    $GEN $BIND/WebSharper.JavaScript.dll --version 10.1.6 --dest ./bindings

    $GEN $BIND/WebSharper.StdLib.dll --version 10.1.6 --dest ./bindings \
      --reference $BIND/WebSharper.JavaScript.dll --spec specs/websharper-stdlib.spec

    $GEN $BIND/WebSharper.Sitelets.dll --version 10.1.6 --dest ./bindings \
      --reference $BIND/WebSharper.JavaScript.dll --reference $BIND/WebSharper.StdLib.dll \
      --spec specs/websharper-sitelets.spec

    $GEN $UI/WebSharper.UI.dll --version 10.1.5 --dest ./bindings \
      --reference $BIND/WebSharper.JavaScript.dll --reference $BIND/WebSharper.StdLib.dll \
      --reference $BIND/WebSharper.Sitelets.dll --spec specs/websharper-ui.spec

    $GEN $UI/WebSharper.UI.Templating.Runtime.dll --version 10.1.5 --dest ./bindings \
      --reference $BIND/WebSharper.JavaScript.dll --reference $BIND/WebSharper.StdLib.dll \
      --reference $UI/WebSharper.UI.dll

A spec is looked up in the explicit `--spec` path, else as
`specs/<pkg-id>.spec` — for the package being generated **and for every
`--reference`**. So `specs/websharper-stdlib.spec` also applies while generating
Sitelets/UI/…, and must be present before regenerating those.

Specs in `specs/` repair what the flat, address-derived naming cannot:

- `specs/websharper-stdlib.spec` — module-name collisions:
  - both `System.DateTime` and `WebSharper.JavaScript.Pervasives.DateTime`
    derive `DateTime`. Neither is a prototype-bearing `default` export, so the
    documented tie-break does not apply and metadata order decides —
    `System.DateTime` came out as `DateTime2`. Named `DateTime` /
    `DateTimeFormat`.
  - a helper that is the *module* of a type takes `<Type>Module` (or a namespace
    qualifier): `FSharpListModule`, `FSharpSetModule`, `LinkedListModule`,
    `DelegateEventModule`, and `ControlEvent` for `WebSharper.Control.Event`
    (`EventModule` is taken by F#'s own `Microsoft.FSharp.Control.EventModule`).
  - generic-vs-helper: the bare name goes to the *generic* type — `Nullable`
    (`System.Nullable<'T>`) + `NullableHelpers`, `Optional`
    (`WebSharper.JavaScript.Optional<'T>`) + `OptionalHelpers`.
  - unrelated helpers in different namespaces: `JavaScriptPervasives`
    (`WebSharper.JavaScript.Pervasives`; `WebSharper.Pervasives` keeps the bare
    name) and `LinqEnumerable` (`System.Linq.Enumerable`; `WebSharper.Enumerable`
    keeps the bare name).
  - nested enumerators are named after their parent: `ListEnumerator`,
    `LinkedListEnumerator`, `DictionaryKeyEnumerator`,
    `DictionaryValueEnumerator`, `DictionaryEnumerator`, `HashSetEnumerator`.
  - deliberately left alone: the **arity families**, where the digit is
    systematic and useful (`Tuple2`..`Tuple9` = `Tuple<'T1>`.., `ValueTuple*`,
    `Union2`..`Union7`, `Func*`, `ThisFunc*`, `Params*`, `IList2` = `IList<'T>`,
    `IEnumerable2`, `Task2`, …).
- `specs/websharper-sitelets.spec` — the **generic** router
  `WebSharper.Sitelets.Router<'T>` takes the bare `Router` (it is the type
  `RouterModule.table` returns and `WebSharper_UI.Router.installHash` takes),
  and the non-generic route matcher becomes `RouterMatcher`; `InferRouter.Router`
  -> `InferRouter` (`RouterModule` is the module of router combinators, `Route`
  the route).
- `specs/websharper-ui.spec` — `WebSharper.UI.Router` refers to
  `WebSharper.Sitelets.Router<'T>`, so UI is generated with the Sitelets
  reference (otherwise the `Router<'T>` argument mis-binds), and the spec merges
  same-named type/module pairs (`Var<'T>` + `Var`) and names a few modules
  (`Html`, `On`).

The native server shadows live in `runtimes/ocaml`, `runtimes/ui-server`
(`WebSharper_UI` + `WebSharper_Sitelets`, the latter implementing the hash router
`WebSharper_UI.Router.installHash` uses) and `runtimes/template`.

Each binding package is a **wrapped** dune library, so identically-named types
across packages do not collide (`WebSharper_JavaScript.Event.t`,
`WebSharper_StdLib.Event.t`, `WebSharper_UI.Event.t`). The shared `Js` module
lives in the unwrapped `websharper-runtime` package. Use `open WebSharper_JavaScript`
(etc.) to bring a package's modules into scope.

Cyclic type hierarchies (e.g. the DOM `EventTarget`/`Node`/`Element`/`Document`
graph) are collapsed to a single shared abstract type so cross-references keep
their real types instead of `Js.t` — `Document.t = Element.t = Node.t =
EventTarget.t`, and `Document.getElementById : Document.t -> string -> Element.t`
(the representative is chosen as the base with the largest subclass tree).

### Packaging referenced assemblies

With `--ws-compile`, the backend runs the WebSharper packager over the
`--reference` assemblies, emitting one ESM module per WebSharper type under
`<out>/<Assembly>/<Type>.js` plus the runtime at
`<out>/WebSharper.Core.JavaScript/Runtime.js`:

    dotnet .../WebSharper.OCaml.dll --ir Main.wsir.json --output out --ws-compile \
      --reference WebSharper.UI.dll --reference WebSharper.StdLib.dll \
      --reference WebSharper.JavaScript.dll

The entry file's calls into those assemblies are emitted as relative ESM imports
(`import … from "./WebSharper.UI/WebSharper.UI.Doc.js"`), so the whole thing runs
in the browser with **no bundler** — see
[`docs/client-bundle.md`](docs/client-bundle.md). (`--package-references` is
parsed but currently a no-op: packaging runs whenever `--ws-compile` has
references.)

## Examples

Each example is a dune project producing a directory of JS. Install the
bindings first, then build:

    opam repo add wsocaml ./bindings
    opam install websharper-javascript

    cd examples/js && dune build && node _build/default/out/Main.js
    cd examples/dom && dune build && node run.mjs _build/default/out

`examples/hello-world` is a wsocaml app: a **DU-based sitelet** (`[@endpoint]`
+ `Sitelet.Infer`, expanded by the frontend) whose Home page **embeds a hydrated
client-side piece** (`WebSharper_ClientServer.hydrate`). `dune build` produces
both tiers via `--emit-server`:

    opam repo add wsocaml ./bindings && opam install websharper-javascript
    opam install ./runtimes/ocaml ./runtimes/ui-server   # websharper-server + websharper-ui-server
    cd examples/hello-world && bash build.sh             # -> out/{client,server}
    ./out/server &                                       # serves http://127.0.0.1:8123/
    node verify.mjs out                                  # SSR + hydration check

(Requires `frontend/` and `backend/` to be built: `cd frontend && dune build`,
`dotnet build backend`.)

`examples/todomvc` is a **TodoMVC** app written with WebSharper.UI **templates**
(the markup is `views/todomvc.html`; `todomvc.ml` fills its holes). Like
`hello-world` it builds both tiers — a client bundle and a native server that
serves the page:

    cd examples/todomvc && bash build.sh
    ./out/server &                         # http://127.0.0.1:8123/

`examples/todomvc-full` is the same app using the WebSharper **SSR split**: the
server renders the template skeleton (`Tmpl.doc ~keepUnfilled:true`) and the
client binds it (`Tmpl.bind`) to reactive `View`/`Var`/`Doc` holes. It shows
nested templates and `.Bind()` working end to end (see `docs/templates.md`).

`dune build` in `examples/hello-world` only type-checks the source (its `dune`
has a `library` stanza so the editor resolves the libraries); the app is built
by `build.sh`, so editing does not trigger a build.

To surface `build.sh` (frontend/codegen/native) errors in VS Code, run the
default build task **wsocaml: build** (`Cmd/Ctrl+Shift+B`): `check.sh` builds and
pipes the output through `scripts/wsocaml-diag.py`, which rewrites OCaml's
multi-line reports into `file:line:col: error|warning: message` so they appear in
the Problems panel.)

`examples/js` references the binding package directly in its `dune` file
(`(libraries websharper-javascript)` and
`%{lib:websharper-javascript:console.ml}`), so `dune build` type-checks the
example against the installed opam package and then emits JS. `examples/dom` is
a jsdom-backed DOM example. `examples/hello` and `examples/basics` compile plain
OCaml units and need no bindings.

## Client/server: sitelets & hydration

A wsocaml app is written once and compiled to both tiers. A `[@website]`
**sitelet** serves pages (`Content.*`) and RPC on the native OCaml server, and
`client`/`hydrate` embed client-side pieces in a server-rendered page.

- `[@rpc]` — the client gets a proxy; the body runs on the native server.
- `[@endpoint "METHOD /path"]` on a DU case + `Sitelet.infer` — the frontend
  generates the router/URL builder from the endpoint variant: `@name` binds a
  payload slot (an inline-record field, or `@0`/`@1`… for a tuple payload) and
  `?key=@name` binds a query parameter. Every scenario is walked through in
  [`docs/routing.md`](docs/routing.md).
- `open WebSharper_ClientServer` then `hydrate (fun () -> view)` /
  `client (fun () -> view)` embed a client-side piece in a page.

The `hydrate`/`client` pipeline:

1. the frontend **lifts** the fragment into a `[@client]` binding
   `let ws<id> () = Doc.runById "<id>" view` (opaque `ws<digits>` id) and replaces
   the call with a marker (`__hydrate`/`__client`);
2. the native server renders the marker: `hydrate` server-renders the view into
   `<div id="<id>" data-ws-key="<id>">…</div>` (SSR); `client` renders it empty
   (client-only);
3. `Content.page` + `Server.serve ~bundle` inject the bundle and, **after** it, a
   bootstrap `<script type="module">globalThis.OCamlRuntime.hydrate()</script>`
   (both deferred module scripts, so the bundle registers client code first);
4. the client bundle registers the lifted binding (`OCamlRuntime.registerClient`);
5. on load `hydrate()` clears each `[data-ws-key]` region and runs the binding
   (`Doc.runById`), re-rendering the same view client-side — currently
   **client-owned** (not node-preserving).

See `examples/hello-world` and `docs/client-server.md` for details.

### Typed JSON

`WebSharper_Json.encode v` / `WebSharper_Json.decode s` serialize any supported
OCaml type in the *same* external representation `[@rpc]`/`[@export]` use, so no
hand-written encoder/decoder is needed:

```ocaml
let save (ts : todo list) =
  Storage.setItem (storage ()) key (WebSharper_Json.encode ts)

let load () =
  try (WebSharper_Json.decode (Storage.getItem (storage ()) key) : todo list)
  with _ -> []
```

The descriptor comes from the value's type at the call site, so annotate
polymorphic callers (`let save (ts : todo list)`). `open WebSharper_Json` also
allows the bare `encode`/`decode` spelling. Client-only today. See
[`JSON.md`](JSON.md) §1.1 for how the frontend/backend/runtime split it.

## Differences from .NET WebSharper

wsocaml reuses WebSharper's AST, runtime and binding packages, so most of the
programming model matches .NET WS. The deliberate differences and the known gaps are
collected in [`docs/ws-differences.md`](docs/ws-differences.md). In brief:

- **Instance members are functions.** Interop APIs are generated as
  `recv -> args -> ret` (e.g. `Var.get : 'a Var.t -> 'a`) rather than CLR instance
  members; OCaml method sends (`obj#m`) are not supported (`Lsend`). This is
  WebSharper's own `[<Prototype(false)>]` representation — WS's default is a JS
  class with prototype methods, reattached to plain/JSON objects via
  `WebSharperRuntime.Create` (`Object.create(ctor.prototype)` + assign).
- **`V` reactive notation** (`V (a.V + b.V)`) is **not supported**: the backend does
  not resolve generic type arguments at `ws:` call sites (so `Macros.V` fails), and
  macro instance accessors like `Var.V` lose their receiver. The flattened spelling
  would be `V.v (Var.v a + Var.v b)`.
- Other gaps (anchors, cross-file templates, `ServerLoad`/`ClientLoad`,
  node-preserving hydration, `int32`/`int64` on the wire) are listed there too.

## Templates

WebSharper.UI-style templates: `[%template "views/card.html"]` expands an HTML
file (with `${…}` and `ws-*`/`data-*` holes) into a typed OCaml module (a
mutable record of holes + pipe combinators) that works on both tiers, with SSR.

```ocaml
module Greeting = [%template "views/greeting.html"]

let g = Greeting.create () |> Greeting.title "Hi" |> Greeting.body "…"
Content.page ~title:"Home" [ Greeting.doc g ]
```

Inner templates (`ws-template`) become submodules; event holes get nominal types
(`MouseEvent.t`, `KeyboardEvent.t`, …) and `_withModel` variants with access to
the instance vars. The `websharper-ocaml-ppx` ppx
(`(preprocess (pps websharper-ocaml-ppx))`) gives the editor full ocaml-lsp
support for `[%template]`. See `docs/templates.md`.


## Tests

    bash backend/tests/run-tests.sh            # build the backend and run all tests
    bash backend/tests/run-tests.sh --no-build # skip the backend build
    bash backend/tests/run-tests.sh --update   # refresh goldens

The harness covers IR fixtures plus apps: the raw-FFI fixture (`apps/`, via
`scripts/build-js-app.sh`) and generated WebSharper bindings (`apps-ws/`, via
`scripts/build-ws-app.sh`).

The full suite is slow, so for incremental work use the kitchen-sink inner loop
and run the full suite only before wrapping up:

    bash scripts/test-quick.sh   # build + run backend/tests/apps-ui/kitchensink

`kitchensink.ml` is a single program that exercises the major features (OCaml/
StdLib, WebSharper macros, HTML combinators, event handling, Var/View reactivity,
and the list/fn interop bridges).

