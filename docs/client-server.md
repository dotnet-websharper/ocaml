# OCaml client/server + hydration — design

Goal: let a single OCaml program be tier-split like WebSharper, so client code
runs in the browser and the server renders HTML + client instructions that a
small runtime *hydrates* on page load — with no F# quotations.

This documents the mechanism and an incremental plan. It builds on what already
exists:

- the OCaml frontend (`frontend/`) emits an IR (`wsocaml-ir-4`) per unit;
- the backend (`backend/`, `--ws-compile`) lowers IR to WebSharper AST and runs
  the WebSharper packager (`Compilation`/`CompileFull`/`packageAssembly`);
- a kitchen-sink app + `scripts/test-quick.sh` give a fast inner loop;
- WebSharper's own model (in `WebSharper.Core`/`WebSharper.StdLib/Html.fs`) uses
  `ClientCode` instructions plus `IUniqueIdSource` for per-element ids and
  `IRequiresResources.Requires` to emit them.

## 1. Boundary (WebSharper model)

The client/server boundary follows WebSharper: **mark what is JS-targeted and
what is a server RPC; everything else stays on the server and is unreachable
from client code.**

- `let[@javascript] f x = …` — a **JS-targeted** (client) value; compiled to the
  client bundle.
- `let[@rpc] f x = …` — a **server** value the client may call; the client gets a
  proxy stub, the server runs the body.
- every other top-level value is **server-only**.

Client code (the `[@javascript]` values) must not reference a server-only value
directly; an `Rpc` call is the only client→server path. A direct reference is a
compile error (enforced by the frontend).

This mirrors WS `[<JavaScript>]` / `[<Rpc>]`: marking JS-targeted functions and
RPCs, with a server-side default.

## 2. Surface

Attributes on structure items (OCaml attributes live on the value binding):

```ocaml
let[@javascript] view = …      (* client *)
let[@rpc] save data = …        (* server, callable from the client *)
let helper x = …               (* server-only; unreachable from client code *)
```

The frontend reads them from the parsetree and emits the marked names in the IR
(`javascript` / `rpc`); the backend consumes them for the client/server split
(RPC proxies, server bundle).

## 3. Compilation pipeline

### Frontend (`frontend/`)

- Before typechecking (`main.ml`), scan the parsetree for `[@javascript]` /
  `[@rpc]` on top-level value bindings; emit `javascript` / `rpc` name lists in
  the IR.
- **Enforce the boundary**: a `[@javascript]` binding that references a
  top-level value which is neither `[@javascript]` nor `[@rpc]` is an error
  (`checkBoundary`).

### Backend (`backend/`)

- Parse the `javascript` / `rpc` marks into the IR.
- On a top-level `let[@rpc] g = fun …`, the client binds `g` to a proxy that
  calls `OCamlRuntime.rpcCall("g", args)`; the real body is collected into a
  **server bundle** `<out>/server/<unit>.js` that registers it via
  `OCamlRuntime.registerRpc`. (The runtime stands in for an HTTP round-trip.)
- The unit is compiled twice: a **client** build (keeps the entry + `[@javascript]`
  code + `rpcCall` proxies; stubs server-only and `[@rpc]` bodies) and a
  **server** build (`<out>/<unit>.server.js`; keeps server-only + `[@rpc]`
  bodies, stubs client code, registers the rpc handlers). Only client code is in
  the client bundle.
- For client code embedded in a rendered view, emit `ClientCode`-style
  instructions (see §4).

### 3.1 Native server (real tier)

The server tier is **native OCaml**, not JS:

- `frontend --emit-server <out.ml>` emits an OCaml program that re-runs the
  server-only + `[@rpc]` definitions (dropping `[@javascript]` code and the
  client entry) and serves them over JSON-RPC, with **type-directed codecs**
  generated from the inferred types (`int`/`float`/`string`/`bool`/`unit`/`list`/
  `option`/`array`).
- `runtimes/ocaml/wsrpc.ml` is a minimal native JSON-RPC server (`unix` sockets).
- The client's `rpcTransport` POSTs over HTTP (`fetch`) when
  `OCamlRuntime.rpcEndpoint` is set.

`scripts/rpc-demo.sh` compiles the *same* source to a JS client and to a native
OCaml server, starts the server, and drives the client RPC over HTTP
(`frontend/test: rpc-server`). The older `<unit>.server.js` JS server bundle
(§3) remains for the in-process test path.

## 4. Server embed + client runtime

Server rendering emits HTML plus instructions, mirroring WebSharper's
`ClientCode`:

- a **placeholder** node carrying `data-ws-key` (and any needed key-indexed data
  in a `<script type="application/json">` blob), or a `ws-<id>` attribute for
  event handlers (as UI already does);
- the client runtime (`ClientRuntime.js`) runs on load:
  1. collect placeholders by key;
  2. import/run the corresponding client code;
  3. restore captured JSON into the scope;
  4. run the code (attach listeners, replace nodes, start views), reusing the
     same `Doc`/`Elt` runtime so hydration is "run the same code again, but
     attach to existing DOM".

Hydration reuses the existing reconciliation in `WebSharper.UI` (the server
marks holes with `ws-<id>`; the client `Doc.Run` finds them). Our job is to feed
the same runtime from OCaml-compiled code.

## 5. Milestones

- **B1 — boundary (done).** `[@javascript]`/`[@rpc]` read from the parsetree,
  emitted in the IR; the frontend rejects a client→server direct reference.
- **B2 — RPC (done).** A top-level `[@rpc]` value's client binding is an
  asynchronous, serialized `OCamlRuntime.rpcCall` proxy (JSON arguments/result,
  a `Promise` over a pluggable transport). The client bundle excludes
  server-only + `[@rpc]` bodies. The server tier is now **native OCaml** (§3.1):
  `--emit-server` generates it from the same source and the client reaches it
  over HTTP. A future revision should add an OCaml async type for `[@rpc]` call
  sites.
- **M3 — first-class client code.** Stable keys by `(assembly, unit, position)`;
  multiple client units; import wiring; `scripts/test-quick.sh` coverage.
- **M4 — UI integration + hydration.** Marked client code as `On.*`/`Attr`
  handlers; server placeholders; `ClientRuntime.js` hydrates a server-rendered
  `Doc` by re-running the OCaml view client-side.
- **M5 — server.** Render-time server code, data embedding.

## 6. Open questions

- How the client "entry" is designated (a `[@javascript]` `main`, or the unit
  itself) — for now the check covers `[@javascript]` bindings only.
- How much of WebSharper's `ClientCode`/`IRequiresResources` pipeline to reuse
  vs. reimplement in OCaml-friendly form.
- Streaming vs. whole-page hydration; partial hydration granularity.
- Cross-.NET-server interop (a non-OCaml server) would need a key +
  serialization contract independent of OCaml source positions.
- Error surfacing for unsupported captures (functions, mutable refs).
