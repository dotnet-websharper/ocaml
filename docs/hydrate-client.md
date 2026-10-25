# `hydrate` / `client` — reference

How a `hydrate`/`client` region works today, end to end. Complements
[`client-server.md`](client-server.md) (design/scope) and
[`codegen.md`](codegen.md) (what lands in `server.ml`); this note is the
implementation walkthrough, from source to served HTML to the runtime.

Line numbers are from `frontend/bin/main.ml` / `backend/Lowering.fs` and will
drift — treat them as pointers, not contracts.

## 1. Surface

Client-facing stubs (what app source typechecks against on the client tier) —
`runtimes/server-api/webSharper_ClientServer.mli`:

```ocaml
val client  : (unit -> WebSharper_UI.Doc.t) -> WebSharper_UI.Doc.t
val hydrate : (unit -> WebSharper_UI.Doc.t) -> WebSharper_UI.Doc.t
val __client  : string -> WebSharper_UI.Doc.t
val __hydrate : string -> (unit -> WebSharper_UI.Doc.t) -> WebSharper_UI.Doc.t
```

Source writes `open WebSharper_ClientServer` and calls
`client (fun () -> view)` / `hydrate (fun () -> view)`. The fragment is lifted to
top level, so it must be **closed** (cannot capture locals).

Native implementation (server tier) — `runtimes/ocaml/webSharper_ClientServer.ml`:

```ocaml
let region id children = [ Ssr.el "div" [ ("id", id); ("data-ws-key", id) ] children ]
let __client  id   = region id []
let __hydrate id f = region id (f ())
let client  _ = failwith "WebSharper_ClientServer.client is expanded by the compiler"
let hydrate _ = failwith "WebSharper_ClientServer.hydrate is expanded by the compiler"
```

So `client` renders an **empty** `data-ws-key` region server-side; `hydrate`
renders the view **inside** the region server-side. `client`/`hydrate` are never
called — the compiler rewrites them.

## 2. Pipeline position

```
parse → transformTemplates → transformInfer → transformClientServer → transformClientEvents
      → checkBoundary → typecheck → { IR (client) | --emit-server → server.ml }
```

Both tiers run the *same* `transformClientServer`. Only `transformClientEvents`
(and `transformTemplates`) take a `~server` flag, and `serverItems` filters at
emission time.

## 3. `transformClientServer` (`main.ml:1458`) — lift the fragment, install the marker

Recognizes `client`/`hydrate` in call position (`csCall`, `:1460`):

| call | marker |
| --- | --- |
| `client (fun () -> view)` | placeholder (`__client`) |
| `hydrate (fun () -> view)` | SSR'd (`__hydrate`) |

For each call it computes a **stable id** from the *printed* fragment
(`id_of`, `:1469`):

```ocaml
"ws" ^ string_of_int (abs (Hashtbl.hash (Pprintast.expression arg)))
```

and does two rewrites from the same fragment:

1. **In place** (marker, `:1493`):
   - `hydrate` → `WebSharper_ClientServer.__hydrate "ws<id>" (fun () -> view)`
   - `client`  → `WebSharper_ClientServer.__client "ws<id>"`
2. **Appended top-level binding** (`binding_value`, `:1502`), inserted after the
   opens/types and before the first value binding (`insert`, `:1556`):
   ```ocaml
   let[@client] ws<id> () = WebSharper_UI.Doc.runById "ws<id>" (view)
   ```

Also, in the fragment: `on.<event>` field access → `On.<event>` (`:1519`).

The two rewrites use the same id because it derives from the fragment text —
that is the cross-tier contract (same trick as the content-hashed event keys,
`AGENTS.md` gotcha 11).

## 4. `transformClientEvents` (`main.ml:1699`) — region vs server-rendered handlers

`~server:true` only for `--emit-server`.

**a) Handlers inside a region are "client-rendered".** The `__hydrate` marker
marks its view (`isHydrateMarker`, `:1755`), and every top-level `[@client]`
binding marks itself (`structure_item`, `:1874`). Inside (`!in_client`), on the
**server** a handler's body is replaced by `fun _ _ -> ()` (`:1769`); on the
**client** it is left inline. There is **no** `ws-on<event>` marker and no lifted
binding — the client attaches the handler when `Doc.runById` re-renders during
`hydrate()`.

Verified: for `div [ on.click (fun _ _ -> Var.set v "after") ]` inside a
`hydrate`, the server build prints `div [On.click (fun _ _ -> ())] …` (both in the
`__hydrate` marker and in the `ws<id>` binding), while the client bundle keeps
`Attr.Handler("click", … e.Set("after"))`.

**b) `on.<event>` on a *server-rendered* element** (outside any region) is lifted
into a top-level `[@javascript]` binding (`wsh<digits>`, key = `Hashtbl.hash` of
the printed handler, `keyOf` `:1720`); then:
- server build → `WebSharper_UI.Attr.create "ws-on<event>" "<key>"` (`marker`, `:1745`),
- client build → `On.<event> <key>`.

A server-rendered handler must be **closed**: if `freeNames` shows it captures a
local, that is a located error (`:1779`). Region handlers are exempt.

The lifted event keys are returned as `eventKeys`.

## 5. Classification and the IR (`main.ml:313`, `:2029`)

- `clientMarks` (`:313`): `js` = names of `[@javascript] ∪ [@export] ∪ [@client]`;
  `rpc`; `srv` (everything else).
- `clientNames` (`:335`): `cli` = names with `[@client]` (the `ws<id>` liftings).
- `checkBoundary` (`:404`): a `js` value that references a `server`-only
  top-level is a located error.
- IR (`:2111`):
  - `javascript`, `rpc`, `server`, `exports` name lists;
  - `clients` = `(cli @ eventKeys)` mapped to `{name; key; index}`, where `index`
    is the value's module-block slot (`topIndex`, `:2064`).

## 6. Client build (backend)

`Lowering.fs`:

- top-level `[@javascript]` and `[@client]` values are **kept** on the client,
  stubbed on the server (`:171`);
- `server`-only top-levels are stubbed on the client (`ServerOnly`, `:173`);
- after the module body, `clientRegs` emits one registration per entry of
  `ir.Clients` (`:658`):
  ```js
  OCamlRuntime.registerClient("<key>", me[<index>]);
  ```

So the bundle tail is:

```js
OCamlRuntime.registerClient("ws204306509", me[k]);   // [@client] ws<id> → Doc.runById …
OCamlRuntime.registerClient("wsh36132450", me[j]);    // lifted server-rendered handler
```

The `[@client]` subroutine is `ws<id> () = Doc.runById "ws<id>" view`. On the
client binding that is `WebSharper.UI.Client.Doc.RunById`
(`bindings/packages/websharper-ui/.../lib/clientDoc.ml:36`).

## 7. Server build (`--emit-server`)

`serverItems` (`:939`) keeps, item by item:

| item | kept in `server.ml`? |
| --- | --- |
| `open WebSharper_UI` / `_Server` / `_ClientServer` | yes |
| any other `open WebSharper_*` (e.g. `WebSharper_JavaScript`) | **dropped** |
| `let[@client] ws<id>` (lifted region) | **yes** |
| `let[@javascript]` / `let[@export]` / lifted `wsh<digits>` | **dropped** |
| `let[@rpc]`, `let` (server-only), `type`/`module`/… | yes |

The filter is literally `js minus clients`, so `[@client]` survives. Marker
attributes are stripped (`stripMarkers`, `:924`). The server items are
typechecked against the **native** packages via `typecheckServer`
(`--server-include` appended last so the shadows win, `:2022`).

Native shadows used at link time:

- `runtimes/ocaml/webSharper_ClientServer.ml` — `__client`/`__hydrate`, `region`;
- `runtimes/ocaml/ssr.ml` — `Ssr.node`, `client_region`, `regions`/`page`;
- `runtimes/ui-server/webSharper_UI.ml` — the `WebSharper_UI` subset, where
  `Doc.runById id d = Ssr.regions_replace id (render d)` (`:73`) and
  `Doc.t = Ssr.node list` is **eager**.

Bootstrap (`emitServer`, `:1067`):

- **with `[@website]`** (sitelet path — `apps-site`, `hello-world`):
  ```ocaml
  WebSharper_Server.Server.serve ~port:8123 ~bundle:"Main" ~static:"…" main
  ```
  The page is `Content.page`, which **inline-renders** the `__hydrate` region.
  `Server.serve` then calls `replace_scripts` (`webSharper_Server.ml:88`) to swap
  `<script ws-replace="scripts">` for:
  ```html
  <script type="module" src="/Main.js"></script>
  <script type="module">globalThis.OCamlRuntime.hydrate();</script>
  ```
  The `[@client] ws<id>` values are **not** called here (the marker rendered them).
- **without `[@website]`, with `[@client]` values** (SSR path — `ssr-demo`,
  `apps-ui`):
  ```ocaml
  Ssr.regions_reset ();
  ws<id> ();        (* Doc.runById id view → Ssr.regions_replace *)
  …
  Wsrpc.serve ~port:8123 (fun _ -> { …; body = Ssr.page ~title:"wsocaml" ~scripts:["/Main.js"] () })
  ```
  `Ssr.page` assembles the page from the `regions` table filled by `Doc.runById`
  (`ssr.ml:69`). This path does not emit the `hydrate()` bootstrap itself; the
  drivers call it (`ssr_client.mjs`).

## 8. Served HTML and the browser

`hydrate` region (server HTML, sitelet path):

```html
<div id="ws204306509" data-ws-key="ws204306509"><div>before</div></div>
```

`client` region: the same `<div … data-ws-key=…></div>` but **empty**.

Browser timeline:

1. parser builds the region + server markup; painted, no listeners (module
   scripts are deferred);
2. `Main.js` runs → `registerClient("ws204306509", …)` (and any `wsh…`);
3. inline `hydrate()` runs.

`backend/Runtime.js`:

```js
function registerClient(key, fn) { (clientCode ||= {})[key] = fn; }

function hydrate() {
  var nodes = doc.querySelectorAll("[data-ws-key]"), n = 0;
  for (var i = 0; i < nodes.length; i++) {
    var fn = store[nodes[i].getAttribute("data-ws-key")];
    if (fn) { nodes[i].textContent = ""; caml_apply(fn, [0]); n++; }   // clear + re-render
  }
  attachEvents();                                                       // wsh… handlers
  return n;
}
```

`attachEvents()` (`:320`) scans for attributes whose name starts with `ws-on`,
looks the suffix up in `clientCode`, and attaches
`el.addEventListener(ev, e => fn(el, e))` once (guarded by `__wsEventsAttached`).

For a region, `caml_apply(fn,[0])` → `ws<id> ()` → `Doc.runById` renders the view
**client-side** into the now-empty region, wiring `Var`/`View`/`On.click`. For
server-rendered handlers (`ws-on<event>`), `attachEvents` wires the registered
`wsh…` binding.

Hydration is therefore **client-owned**: the region is cleared and re-rendered,
not adopted node-by-node. It looks seamless only because the initial markup
matches. Preserving node identity (focus/scroll/input/`ws-hole`) is the deferred
`ws-hole` work — see [`client-server.md`](client-server.md) §4 and §6.

## 9. Invariants / gotchas

- **Ids are content-derived** (`ws<digits>` from `Pprintast` of the fragment):
  same source ⇒ same id on both tiers. Any change to the derivation must stay
  consistent across builds.
- **Event keys are content-derived** (`wsh<digits>`): the server marker and the
  client registration must agree (`AGENTS.md` gotcha 11; locked by the site test).
- **Handlers inside a region** are noop'd on the server and kept inline on the
  client; **handlers on server-rendered elements** become `ws-on<event>` +
  `wsh…`. Region handlers need not be closed; server-rendered ones must be.
- **`ws-on<event>` is shared with templates** (any `ws-on*` is an event hole;
  `attachEvents` only picks registered keys) — `AGENTS.md` gotcha 10.
- The `[@client] ws<id>` binding is kept in `server.ml`, so anything it
  references must link against the native shadows.
- Event names: `clientEventNames` lists seven (`click`, `dblclick`, `change`,
  `input`, `keydown`, `keyup`, `submit`), but only `click`/`change`/`input`/
  `submit` resolve client-side (the binding spells `dblClick`/`keyDown`/`keyUp`
  in camelCase; `AGENTS.md` gotcha 9).
- Two server page paths (sitelet `Content.page` vs no-website `Ssr.page`) with
  different bootstrap ownership.

## 10. Tests, demos, related docs

- Runtimes/stubs: `runtimes/server-api/webSharper_ClientServer.mli`,
  `runtimes/ocaml/webSharper_ClientServer.ml`, `runtimes/ocaml/ssr.ml`,
  `runtimes/ocaml/ssr_client.mjs`, `backend/Runtime.js`.
- Drivers/tests: `scripts/ssr-demo.sh`, `scripts/site-demo.sh`;
  `backend/tests/apps-ui/wsclient.ml` + `backend/tests/ssr.out`;
  `backend/tests/apps-site/wssite.ml` + `runtimes/ocaml/site_client.mjs` +
  `backend/tests/site.out`.
- Example: `examples/hello-world`.
- Docs: [`client-server.md`](client-server.md) §4/§4.1/§7 (design, scope),
  [`codegen.md`](codegen.md) §2–§4 (the generated `server.ml`).
