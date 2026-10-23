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
  generated from the inferred types (see §3.2).
- `runtimes/ocaml/wsrpc.ml` is a minimal native JSON-RPC server (`unix` sockets).
- `[@rpc]` handlers return `'a Async.t`; the generated handler runs it
  synchronously (`Async.run_sync`, `runtimes/ocaml/async.ml`) and encodes the
  result.
- The client's `rpcTransport` POSTs over HTTP (`fetch`) when
  `OCamlRuntime.rpcEndpoint` is set.

### 3.2 External representation (RPC wire = JS API)

Values cross the OCaml↔JS boundary in a **JS-idiomatic external representation**
(shared by RPC and `[@export]`); the internal OCaml runtime representation is
unchanged:

| OCaml value | external (JS / JSON) |
| --- | --- |
| `int` / `float` | number |
| `bool` | boolean |
| `string` | string |
| `char` | 1-char string |
| `unit` | `null` |
| `list` / `array` | array |
| `option` | `None` → `null`, `Some x` → `x` |
| tuple | array `[a, b]` |
| record | object `{ x, y }` (field names) |
| variant | `{"$":"Case","$0":a,...}`; constants `{"$":"Case"}` |

**Native server** (`--emit-server`): the codecs (`ofJson`/`toJson` in
`frontend/bin/main.ml`) are generated from the inferred types to/from this
representation. **JS side** (client `rpcCall` + `[@export]`): the frontend emits
a compact **type descriptor** per rpc/export into the IR (schema
`wsocaml-ir-5`); a runtime marshaller (`Runtime.js`) converts between the OCaml
runtime representation and the external one.

Supported: `int`/`float`/`string`/`bool`/`char`/`unit`, `list`, `option`,
arrays, tuples, records, (regular) variants and `result`, nested. **Recursive**
record/variant types are supported, *specialized per concrete instantiation*
(so a generic `'a tree` works at `int`/`string`/…); polymorphic recursion is
refused. Boxed integers (`int32`/`int64`/`nativeint`) are rejected with a clear
error. `scripts/rpc-data.sh` round-trips a
record/variant/recursive-tree/array/tuple/list/option workload through a native
server (`frontend/test: rpc-data`).

### 3.3 Interop: `[@export]` and JS consumers

Top-level values marked `[@export]` are part of the unit's **JS API**:

- the backend emits `export const f = …` / `export function f(a, b) { … }` —
  **uncurried**, marshalling arguments/results via the external representation;
- identifiers are StrongName'd so the packager does not rename them;
- the frontend emits a **`.d.ts`** (`frontend --dts <path>`), e.g.
  ```ts
  export type shape = { $: "Dot" } | { $: "Circle"; $0: number } | …;
  export type point = { x: number; y: number };
  export function move(a0: point): point;
  export function area(a0: shape): number;
  ```
- `[@export]` values are treated as client code for the boundary/split (kept on
  the client, stubbed on the server).

`scripts/build-ws-app.sh` emits named exports and `Main.d.ts`;
`backend/tests/apps-ws/wlib.mjs` is a **plain (non-OCaml) JS consumer** that
imports the compiled library and calls `add`/`move`/`area`/`total`
(`frontend/test: ws wlib`, with `wlib.dts` as the declaration golden).

`scripts/rpc-demo.sh` compiles the *same* source to a JS client and to a native
OCaml server, starts the server, and drives the client RPC over HTTP
(`frontend/test: rpc-server`). The older `<unit>.server.js` JS server bundle
(§3) remains for the in-process test path.

## 4. Server embed + client runtime

Server rendering emits HTML plus placeholders, mirroring WebSharper's
`ClientCode`:

- a `[@client]` top-level value (`unit -> unit`, typically rendering a view into
  a mount point via `Doc.runById`) is registered in the client bundle under the
  stable key `<Unit>.<name>`;
- the server emits a **placeholder** node
  `<(div) id="..." data-ws-key="<Unit>.<name>">`;
- the client runtime runs on load: the served page includes
  `<script type="module">globalThis.OCamlRuntime.hydrate()</script>` **after** the
  bundle script, so the bundle registers the client code first; `hydrate()`
  collects `[data-ws-key]` placeholders, looks up the registered client code,
  clears the placeholder (the client owns the region) and runs it, reusing the
  same `Doc`/`Elt` runtime. It then calls `attachEvents()` to wire up any
  server-rendered `on.<event>` handlers (§4.1).

Example:

```ocaml
let[@client] app () =
  Doc.runById "app" (div [] [ Doc.text "hello" ])
```

```html
<div id="app" data-ws-key="Main.app">loading…</div>
<script type="module">
  import './Main.js'; OCamlRuntime.hydrate();
</script>
```

**Server-side rendering (SSR) of the compiled view:** a `[@client]` value
(`unit -> unit`, e.g. `Doc.runById "app" (view ())`) is compiled for **both
tiers** — the client against the generated `WebSharper_UI` binding, the server
against the native shadow `runtimes/ocaml/wsui_server.ml` (a subset:
`Doc`/`Var`/`View`/`Attr`/`On` + the HTML combinators). `--emit-server` rewrites
`open WebSharper_UI*` to the shadow, keeps `[@client]` values, runs them at
startup (their `Doc.runById` renders into regions via `runtimes/ocaml/ssr.ml`),
and serves `Ssr.page` (each region as
`<div id="…" data-ws-key="…">server markup</div>`) through `Wsrpc.serve ~page`.
The client then hydrates each region with `OCamlRuntime.hydrate()`.

`scripts/ssr-demo.sh` (`frontend/test: ssr`) builds the client bundle and the
native server from the *same* `apps-ui/wsclient.ml`, fetches the served page,
hydrates in jsdom, and clicks (SSR `before` -> hydrate -> `after`).

Scope: hydration is **client-owned** — the client re-renders the region (with
identical initial markup, so it is seamless). Node-identity-preserving
reconciliation (reusing the server DOM tree, preserving focus/scroll/input)
requires implementing WebSharper's `ws-hole`/`ws-attr-holes` server-render
protocol (template-based) in the shadow; it is future work.

### 4.1 Server-rendered event handlers

An `on.<event> handler` on a **server-rendered** element (i.e. outside a
`client`/`hydrate` region) has no server-side effect, and its body is client-only
code that cannot link natively. The compiler lifts the handler into a top-level
`[@javascript]` binding under a stable, content-derived key and renders a marker
attribute in its place:

```ocaml
button [ on.click (fun el _ -> Element.setAttribute el "data-clicked" "yes") ] [ text "go" ]
```
```html
<button ws-onclick="wsh1061593301">go</button>
```

- The key is a hash of the handler's printed source (`wsh<digits>`), interned per
  unit, so the **same handler text gets the same key in every build** (server and
  client) and repeated occurrences share one binding.
- The client build registers the lifted binding
  (`OCamlRuntime.registerClient(key, …)`) and `hydrate()` then runs
  `attachEvents()`: it scans for `ws-on<event>` attributes, looks the value up in
  the registered store, and attaches a listener calling the handler with
  `(element, event)`.
- Handlers must be **closed**: one that captures a local of the enclosing scope
  cannot be lifted and is a located error —
  `this event handler is rendered by the server, so it must be closed; it
  captures the local '<name>'`.
- Handlers **inside** a `client`/`hydrate` region are unaffected: the client
  renders (and re-renders) them, so the server only drops the handler body (it
  may use client-only bindings) and the client keeps it inline.

The attribute family is shared with templates, where `ws-on<event>="Name"` names
a template hole; `attachEvents` only attaches values that are registered keys, so
the two mechanisms do not interfere.

## 5. Milestones

- **B1 — boundary (done).** `[@javascript]`/`[@rpc]` read from the parsetree,
  emitted in the IR; the frontend rejects a client→server direct reference.
- **B2 — RPC (done).** A top-level `[@rpc]` value's client binding is an
  asynchronous, serialized `OCamlRuntime.rpcCall` proxy (JSON arguments/result,
  a `Promise` over a pluggable transport). It returns `'a Async.t`: the client
  `Async` is the **generated** `WebSharper_JavaScript.Async.t` (an alias of the
  generic, promise-backed `WebSharper_JavaScript.Promise.t`), so client code
  sequences calls with `Async.bind`/`Async.map`/`Async.run`. The client bundle
  excludes server-only + `[@rpc]` bodies. The server tier is now **native
  OCaml** (§3.1): `--emit-server` generates it from the same source, unwrapping
  the handler's `'a Async.t` (`Async.run_sync`) before encoding, and the client
  reaches it over HTTP.
- **M3 — first-class client code.** Stable keys by `(assembly, unit, position)`;
  multiple client units; import wiring; `scripts/test-quick.sh` coverage.
- **M4 — UI integration + hydration (done).** `[@client]` values are registered
  under `data-ws-key` (name) and hydrated by `OCamlRuntime.hydrate()`. **SSR of
  the compiled view**: the same view source compiles against `WebSharper_UI`
  (client) and the native `Wsui_server` shadow (server); `--emit-server` renders
  it into regions and serves `Ssr.page` (`scripts/ssr-demo.sh`, test `ssr`).
  Remaining: node-identity-preserving reconciliation (WS `ws-hole` protocol).
- **M5 — server (done, first cut).** The server is a first-class entity: a
  `Sitelet<'T>` (typed endpoints) marked `[@website]`, `Content.Json/Text/Xml/
  Html/Page`, and `Server.serve`. `Sitelet.Infer` is **compiler-expanded** into
  `Sitelet.make route link` with a router/URL-builder generated from the endpoint
  variant + `[@endpoint "GET /path/@name"]` (`@name` binds a payload slot — a
  record field, or `@0`/`@1`… for a tuple payload; see §7). `Content.Page`
  renders the view and injects the bundle into the
  `ws-replace="scripts"` placeholder. `WebSharper_ClientServer.client`/`hydrate`
  (both `unit -> Doc`) are lifted into `[@client]` bindings under opaque
  `ws<digits>` ids; the server renders the marker (hydrate also SSR-renders the
  view) and the client hydrates the `data-ws-key` region. The generated server
  (`--emit-server`) registers `[@rpc]` handlers and runs
  `Server.serve ~port ~bundle ~static <sitelet>`. See §7. Node-identity
  reconciliation (`ws-hole`) still deferred.

## 6. Open questions

- How the client "entry" is designated (a `[@javascript]` `main`, or the unit
  itself) — for now the check covers `[@javascript]` bindings only.
- How much of WebSharper's `ClientCode`/`IRequiresResources` pipeline to reuse
  vs. reimplement in OCaml-friendly form.
- Streaming vs. whole-page hydration; partial hydration granularity.
- Cross-.NET-server interop (a non-OCaml server) would need a key +
  serialization contract independent of OCaml source positions.
- Error surfacing for unsupported captures: a server-rendered `on.<event>`
  handler that captures a local is now a located error (§4.1); other captures
  (functions, mutable refs) still surface as generated-code type errors.

## 7. The server (sitelet)

Same source, both tiers; native server (no templating):

```ocaml
open WebSharper_ClientServer
open WebSharper_Server

type endpoint =
  | Home        [@endpoint "GET /"]
  | User of int [@endpoint "GET /user/@0"]
  | Search of { q : string; page : int } [@endpoint "GET /search?q=@q&page=@page"]

let[@rpc] add a b = Async.return (a + b)

let[@website] main =
  Sitelet.infer (fun (ctx : endpoint context) ep ->
    match ep with
    | Home ->
        Content.page
          ~title:"Home"
          [
            h1 [] [text "Home"];
            hydrate (fun () ->
              let v = Var.create "before" in

              div [
                  on.click (fun _ _ -> Var.set v "after")
              ] [
                  textView (Var.view v)
              ]
            );
            (* server-rendered element with a client handler (§4.1) *)
            button
              [ on.click (fun el _ -> Element.setAttribute el "data-clicked" "yes") ]
              [ text "click me" ]
          ]
    | User id ->
        Content.page
          ~title:"User"
          [
            h1 [] [text (Printf.sprintf "User %d" id)];
            p [] [text (Printf.sprintf "link=%s" (ctx.link (User (id + 1))))]
          ]
    | Search s ->
        Content.text (Printf.sprintf "Search:%s:%d" s.q s.page)
  )
```

- `WebSharper_Server` (`runtimes/ocaml/webSharper_Server.{mli,ml}`): `Request`/
  `Response`/`context` (`Link`, `Request`); `Content`; `Sitelet<'T>`
  (`make`/`empty`/`(+)`/`infer`); `Server.serve ?port ?static ?bundle`.
- The `.mli` is shared: the frontend typechecks against the generated
  `WebSharper_UI`; the native server links the `WebSharper_UI` shadow
  (`runtimes/ui-server/webSharper_UI.ml`, same module name) + the impl. So a
  view compiles unchanged on both tiers.
- `Content.Page` emits `<!doctype html>…<script ws-replace="scripts"></script>`;
  `Server.serve ~bundle` replaces that with `<script type="module" src="/<bundle>.js">`.
- `Sitelet.Infer` is expanded **before typing**: the endpoint variant (its
  constructors carry `[@endpoint …]`) yields `route : request -> endpoint option`
  and `link : endpoint -> string`.
- `[@endpoint "METHOD /path"]` declares one constructor's route. Non-`@` path
  segments match literally; each `@name` binds a **payload slot**, and the
  `@names` must form a **bijection** over the payload (a located error otherwise).
  The URL order follows the endpoint string, not the declaration order:
  - an **inline record** payload is addressed by **field name**:
    `| User of { id : int; name : string } [@endpoint "GET /user/@name/@id"]`
    routes `/user/<name>/<id>` and links `User { id = 5; name = "bob" }` to
    `/user/bob/5` (`link … /user/@id/@name` would swap them);
  - a **tuple** payload is positional: its slots are the **argument indexes**,
    so `| Move of int * string [@endpoint "PUT /move/@1/@0"]` takes argument 0
    from the second segment;
  - `?key=@name` binds a **query parameter** (both the key and the slot are
    significant); every query item must have that shape.
  Slot types must be `int`/`string`/`bool`/`float` (parsed on the way in,
  formatted on the way out). A missing or malformed query parameter, or a path
  that doesn't match, yields `None` (404).
- `WebSharper_ClientServer.client`/`hydrate (fun () -> view)` are lifted into
  `let ws<id> () = Doc.runById "<id>" view` `[@client]` bindings (opaque
  `ws<digits>` id) and replaced by a marker node; the runtime hydrates each
  `[data-ws-key]` region. Fragments must be closed (no captures).
- `on.<event> handler` on a **server-rendered** element is lifted into a
  `[@javascript]` binding (`wsh<digits>` key) and rendered as a
  `ws-on<event>="<key>"` marker, which the client's `attachEvents()` wires up
  (§4.1); the handler must be closed.
- `--emit-server` emits `Wsrpc.register "name" …` per `[@rpc]` and
  `WebSharper_Server.Server.serve ~port:8123 ~bundle ~static <sitelet>`; `--static`
  serves the client build dir (`text/javascript`).
- `scripts/site-demo.sh` (`frontend/test: site`) drives it: SSR pages (`/`,
  `/user/5`, `/echo/…`, `/search?q=…&page=…`), injected scripts, hydration +
  click, a server-rendered element with a client handler (SSR marker →
  `attachEvents` → click), generated `link` round-trips, RPC, static asset.
- Deferred: node-identity reconciliation (`ws-hole`/`ws-attr-holes`), most
  sitelet combinators (`Sum`/`Shift`/`Protect`), `Content.Json` codecs,
  sessions/cookies — and see §7.2 for endpoint routing.

### 7.1 Source conventions

- `open WebSharper_ClientServer` and use unqualified `hydrate`/`client`.
- Use `text`/`textView` from `open WebSharper_UI.Html` (no `Doc.` prefix).
- Event handlers are `on.<event>` (lowercase, e.g. `on.click`); the compiler
  rewrites them to `On.<event>`. On a server-rendered element the handler is
  lifted and the element carries a `ws-on<event>` marker instead, so the handler
  must be closed (no locals from the enclosing scope) — see §4.1.
- A DU sitelet is a single `let[@website] main = Sitelet.infer (fun _ ep -> …)`
  (lowercase `Sitelet.infer`); `render` is inlined rather than a separate value.
- **Every** constructor of the endpoint variant must carry an
  `[@endpoint "METHOD /path"]` attribute; `@name` binds a payload slot — a record
  field name (`| User of { id : int; name : string } [@endpoint "GET /user/@name/@id"]`)
  or the argument index for a tuple payload (`| Echo of string [@endpoint "GET /echo/@0"]`);
  `?key=@name` binds a query parameter. A constructor without the attribute, an
  unknown/duplicate/unbound slot, or a tuple slot that isn't `@<index>` is a
  located compile error.
- HTML combinator layout:
  - short combinators are one-liners: `h1 [] [text "…"]` (no inner padding);
  - an **empty or single** attribute list stays on the element's line, and the
    inner-content list opener follows it (`p [] [ … ]`);
  - **event handlers** are written as an **expanded** attribute list, with `] [`
    joining the attribute-list close and the content-list open:
    ```ocaml
    div [
        on.click (fun _ _ -> Var.set v "after")
    ] [
        textView (Var.view v)
    ]
    ```
- `fun () ->` / `fun _ _ ->` bodies: kept on the same line when trivial
  (`on.click (fun _ _ -> Var.set v "after")`), broken onto a new line after `->`
  when non-trivial (`hydrate (fun () ->` … `)`).

```ocaml
let[@website] main =
  Sitelet.infer (fun (_ : endpoint context) ep ->
    match ep with
    | Home ->
        Content.page
          ~title:"Hello, world!"
          [
            h1 [] [text "Hello, world!"];
            p [] [text "Served by websharper-server, hydrated by WebSharper.UI."];
            hydrate (fun () ->
              let v = Var.create "before" in

              div [
                  on.click (fun _ _ -> Var.set v "after")
              ] [
                  textView (Var.view v)
              ]
            )
          ]
  )
```

### 7.2 Endpoint routing: status

`[@endpoint …]` is compiled by `endpointPlan`/`genRoute`/`genLink`
(`frontend/bin/main.ml`); the router and the URL builder are generated from the
same plan, so a route parses exactly what it links.
[`routing.md`](routing.md) has a worked example of every scenario (constant,
positional and record payloads, reordered URLs, query parameters, methods,
diagnostics and the planned extensions).

**Implemented**

- `@name` ↔ payload-slot binding: inline records by **field name** (URL order
  free), tuple payloads by **argument index** (`@0`, `@1`, …; the URL order is
  free too, since the index *is* the slot). Checked as a bijection —
  unknown slot, duplicate binding, unbound slot and a non-index tuple name are
  located errors.
- Query parameters (`?key=@name`); a missing or unparseable parameter (or a
  malformed query item) means the route doesn't match (`None`, i.e. 404).
- Method + literal path segments; codecs `int`/`string`/`bool`/`float`
  (`parseArg`/`fmtArg`), both directions.
- Diagnostics, all at the constructor and normalized by `diag.exe`; goldens in
  `backend/tests/errors/*.ml`: missing `[@endpoint]`, unknown slot, duplicate
  binding, unbound slot, tuple name, query-item syntax (including an empty query
  part / the unsupported `@page?`), unsupported slot type. Examples of each:
  [`routing.md`](routing.md) §12.

**Not implemented (possible extensions)**

- Optional segments (e.g. `@page?`), catch-all/rest segments (`@rest...`), and
  defaults for missing query parameters.
- Codec-by-name annotations (`@x:slug`) so a slot can use a user-defined type
  instead of the four built-ins.
- Payloads that are **named record types** (`| User of user`): only inline
  records are resolved; a named payload would need a lookup of the type's
  declaration.
- Dotted/nested slot names (`@date.y`) for structured payloads.
- Several `[@endpoint]` aliases per constructor (today only the first attribute
  is read).
- Literal query requirements (`?flag`, `?k=v`) — every query item must currently
  be `key=@name`.
- URL percent-encoding/decoding: `link` formats values raw and the server's
  `parse_query` doesn't decode, so values containing `/`, `&`, `?` or spaces are
  not round-tripped.
- Route-ambiguity detection (two constructors matching the same method+segments):
  the first `[@endpoint]` in declaration order wins.
