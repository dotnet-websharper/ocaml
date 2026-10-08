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
| `bindings-legacy/` | earlier hand-authored bindings (used by the app tests) |
| `examples/` | dune projects built on the generated bindings |
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
across packages do not collide (`Websharper_javascript.Event.t`,
`Websharper_stdlib.Event.t`, `Websharper_ui.Event.t`). The shared `Js` module
lives in the unwrapped `websharper-runtime` package. Use `open Websharper_javascript`
(etc.) to bring a package's modules into scope.

Cyclic type hierarchies (e.g. the DOM `EventTarget`/`Node`/`Element`/`Document`
graph) are collapsed to a single shared abstract type so cross-references keep
their real types instead of `Js.t` — `Document.t = Element.t = Node.t =
EventTarget.t`, and `Document.getElementById : Document.t -> string -> Element.t`
(the representative is chosen as the base with the largest subclass tree).

## Examples

Each example is a dune project producing a directory of JS. Install the
bindings first, then build:

    opam repo add wsocaml ./bindings
    opam install websharper-javascript

    cd examples/js && dune build && node _build/default/out/Main.js
    cd examples/dom && dune build && node run.mjs _build/default/out

`examples/js` references the binding package directly in its `dune` file
(`(libraries websharper-javascript)` and
`%{lib:websharper-javascript:console.ml}`), so `dune build` type-checks the
example against the installed opam package and then emits JS. `examples/dom` is
a jsdom-backed DOM example. `examples/hello` and `examples/basics` compile plain
OCaml units and need no bindings.

## Tests

    bash backend/tests/run-tests.sh            # build the backend and run all tests
    bash backend/tests/run-tests.sh --no-build # skip the backend build
    bash backend/tests/run-tests.sh --update   # refresh goldens

The harness covers IR fixtures plus apps: legacy bindings (`apps/`) and generated
WebSharper bindings (`apps-ws/`, via `scripts/build-ws-app.sh`).
