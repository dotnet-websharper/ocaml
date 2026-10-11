# wsocaml — an OCaml frontend for WebSharper

`wsocaml` compiles OCaml to JavaScript through WebSharper's AST and runtime:

```
Parse -> Typemod.type_structure -> Translmod.transl_implementation -> Lambda.program
  -> wsocaml-ir-4 -> WebSharper AST -> JavaScript
```

OCaml itself handles typing and pattern-match compilation; the frontend serializes
Lambda into `wsocaml-ir-4`, and the backend lowers it to WebSharper AST and emits JS.

## Layout

| Path | Purpose |
| --- | --- |
| `frontend/` | OCaml (dune) frontend: `.ml` → `wsocaml-ir-4` |
| `backend/` | F#/.NET backend: `.wsir.json` → `.js` (also handles WebSharper bindings) |
| `binding-adaptor/` | F# tool: WebSharper binding assembly → OCaml opam package |
| `bindings/` | local opam repository of generated bindings (`websharper-xxx`) |
| `bindings-legacy/` | raw-FFI test fixture (`gen-bindings.py`), used by the `jsbind`/`dom` emit tests |
| `runtimes/ocaml/` | `websharper-server`: representation-agnostic sitelets, Content, SSR nodes, HTTP |
| `runtimes/ui-server/` | `websharper-ui-server`: the native `WebSharper_UI` shadow (converts to `Ssr.node`) |
| `examples/` | dune projects built on the generated bindings / `websharper-server` |
| `scripts/` | build/test helpers |
| `backend/tests/` | test harness (IR fixtures + apps) |

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
automatically:

    dotnet .../binding-adaptor.dll gen WebSharper.UI.dll --version 10.1.5 --dest ./bindings \
      --reference .../WebSharper.JavaScript.dll --reference .../WebSharper.StdLib.dll

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

The backend can run the WebSharper packager over `--reference` assemblies
(`--package-references`), emitting one ESM module per type under
`<out>/<Assembly>/<Type>.js` plus the WebSharper runtime at
`<out>/WebSharper.Core.JavaScript/Runtime.js`:

    dotnet .../WebSharper.OCaml.dll --ir Main.wsir.json --output out --package-references \
      --reference WebSharper.UI.dll --reference WebSharper.StdLib.dll

(Linking the entry's calls to these packaged modules is the remaining step.)

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
  generates the router/URL builder from the endpoint variant.
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

