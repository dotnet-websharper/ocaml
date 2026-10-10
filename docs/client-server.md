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
- Include only JS-targeted code in the client bundle; emit a separate server
  bundle for `[@rpc]` bodies and server-only code.
- Lower `Rpc` references from client code to a proxy stub (the server handler
  is registered in the server bundle).
- For client code embedded in a rendered view, emit `ClientCode`-style
  instructions (see §4).

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
- **B2 — RPC.** Lower `[@rpc]` calls from client code to a proxy; a server
  bundle runs the bodies; a minimal remoting runtime.
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
