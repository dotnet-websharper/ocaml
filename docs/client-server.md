# OCaml client/server + hydration — design

Goal: let a single OCaml program be tier-split like WebSharper's
`Client`/`Server`, so client-only code runs in the browser and the server emits
HTML + client instructions that a small runtime *hydrates* on page load — with
no F# quotations.

This documents the mechanism and an incremental plan. It builds on what already
exists:

- the OCaml frontend (`frontend/`) emits an IR (`wsocaml-ir-4`) per unit;
- the backend (`backend/`, `--ws-compile`) lowers IR to WebSharper AST and runs
  the WebSharper packager (`Compilation`/`CompileFull`/`packageAssembly`);
- a kitchen-sink app + `scripts/test-quick.sh` give a fast inner loop;
- WebSharper's own model (in `WebSharper.Core`/`WebSharper.StdLib/Html.fs`) uses
  `ClientCode` instructions plus `IUniqueIdSource` for per-element ids and
  `IRequiresResources.Requires` to emit them.

## 1. Model

A source unit is compiled into **server** output and zero or more **client**
units. Marked closures decide placement:

- `client (fun args -> body)` — `body` is compiled into a client unit; at the
  use site it becomes a value that, when the server renders, emits a *client
  reference* (an id + serialized captured environment + a client instruction),
  and on the client is replaced by the real function.
- `server (fun args -> body)` — `body` runs at render time; never shipped.

Both tiers are OCaml, so `client`/`server` bodies are ordinary OCaml and can call
the generated bindings (`Elt`/`Doc`/`Var`/`On`/…).

### Keys

Each marked closure gets a stable key derived from
`(assembly, unit/module ident, source position, ordinal)`. The server embed and
the client unit compute the same key, so hydration can match them. Content hash
is the fallback when positions are unavailable.

## 2. Surface API

New binding package `websharper-clientserver` (hand-written, like a small
facade), providing a module users `open`:

```ocaml
open WebSharper_ClientServer

(* a client-only value; `run` applies it *)
let bump = client (fun (el : Element.t) (ev : Event.t) -> count := !count + 1)

(* server-only, runs during render *)
let greeting = server (fun () -> read_from_db ())
```

An OCaml `external` whose result is a function type is **uncurried** by OCaml
(the arity counts every arrow up to a non-function result), so
`('a -> 'b) -> ('a -> 'b)` would be compiled as a 2-argument primitive and the
closure would arrive as a variable, not a literal. M1 therefore uses an opaque
wrapper plus an explicit application:

```ocaml
type ('a, 'b) fn
external client : ('a -> 'b) -> ('a, 'b) fn   = "wsclient:client" "wsclient:client"
external server : ('a -> 'b) -> ('a, 'b) fn   = "wsclient:server" "wsclient:server"
external run    : ('a, 'b) fn -> 'a -> 'b      = "wsclient:run"    "wsclient:run"

let f = client (fun x -> x + 1) in run f 41
```

`run` is applied by the marker's own lowerer; `f` is the opaque handle returned
by `client`. (A future revision may expose a coercion or inlined facade so call
sites read `f 41`.)

The markers are `external`s recognized by the backend by primitive name; no
frontend change is needed (the frontend already lowers `external` calls to
`ccall` with the primitive name).

## 3. Compilation pipeline

### Frontend (`frontend/`)

Recognize calls to the marker functions (`WebSharper_ClientServer.client` /
`server`):

- **`client f`**: emit an IR node `ClientClosure(key, params, bodyIR, captures)`.
  The `bodyIR` is also written to a **client unit** file that is compiled
  separately (same as the entry, but marked client-only).
- **`server f`**: emit `ServerClosure(key, params, bodyIR)` evaluated at render.

IR additions (schema `wsocaml-ir-4` → add fields, back-compatible):

```
{ "tag": "client", "key": "...", "params": [...], "body": <ir>, "captures": [...] }
{ "tag": "server", "key": "...", "params": [...], "body": <ir> }
```

### Backend (`backend/`)

- Lower `ClientClosure`/`ServerClosure` to WebSharper AST.
- For a `client` closure used in a rendering position, emit a
  `ClientCode`-style instruction bundle (see §4) rather than a direct call.
- Package the client unit(s) as ESM modules (as `packageReferences` already
  does) and load them from the runtime.
- Captured environment: each free variable of the closure becomes a JSON value
  (`ClientJsonData`) restored on the client into the closure's scope.

### Client units

A client unit is compiled by the same pipeline with `--client`, producing
`<Key>.js` exporting the closure (and its imports). The runtime imports it by
key.

## 4. Server embed + client runtime

Server rendering of a marked value emits HTML plus instructions, mirroring
WebSharper's `ClientCode`:

- a **placeholder** node carrying `data-ws-key="<Key>"` (and any needed
  `<Key>`-indexed data in a `<script type="application/json">` blob), or a
  `ws-<id>` attribute for event handlers (as UI already does);
- the client runtime (`ClientRuntime.js`) runs on load:
  1. collect placeholders by key;
  2. import the client unit `<Key>.js`;
  3. restore captured JSON into the closure;
  4. run the closure (attach listeners, replace nodes, start views), reusing the
     same `Doc`/`Elt` runtime so hydration is "run the same code again, but
     attach to existing DOM".

Hydration reuses the existing reconciliation in `WebSharper.UI` (the server
marks holes with `ws-<id>`; the client `Doc.Run` finds them). Our job is to feed
the same runtime from OCaml-compiled code.

## 5. Milestones

- **M1 — plumbing.** `client`/`server` markers recognized frontend→IR→backend;
  a closure compiles as a client unit; a bare call round-trips: server emits a
  call node, client runs it and returns a value observable in a test. No DOM.
- **M2 — capture.** Serialize/restore the closure's free variables as JSON;
  verify a captured OCaml value is visible client-side.
- **M3 — first-class units.** Stable keys by `(assembly, unit, position)`;
  multiple client units; import wiring; `scripts/test-quick.sh` coverage.
- **M4 — UI integration + hydration.** `client` closures as `On.*`/`Attr`
  handlers; server placeholders; `ClientRuntime.js` hydrates a server-rendered
  `Doc` by re-running the OCaml view client-side.
- **M5 — `server`.** Render-time `server` closures, data embedding.

## 6. Open questions

- Marker recognition: by FQ name in the frontend vs. a special `external` tag the
  backend lowers — the latter keeps the frontend generic but needs the frontend
  to pass the closure body through.
- How much of WebSharper's `ClientCode`/`IRequiresResources` pipeline to reuse
  vs. reimplement in OCaml-friendly form.
- Streaming vs. whole-page hydration; partial hydration granularity.
- Cross-.NET-server interop (a non-OCaml server) would need a key +
  serialization contract independent of OCaml source positions.
- Error surfacing for closures capturing non-serializable names (functions,
  mutable refs) — start by rejecting unsupported captures with a clear message.

## Status

- **M1 done**: markers recognized by the backend (`wsclient:client`/`server`/`run`); a
  `client` closure compiles to a standalone unit `<out>/clientserver/<key>.js`.
- **M2 done**: the closure's free variables are rewritten to reads from an
  environment object and the unit is emitted as a factory `(env) => closure`;
  the entry registers the captured values as JSON (`OCamlRuntime.registerClient`).
- Next: **M3** (stable keys, multiple/units import wiring) and **M4** (UI
  integration + hydration).

Start with **M3**.
