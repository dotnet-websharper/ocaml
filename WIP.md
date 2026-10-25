# WIP

Scratch roadmap for `wsocaml`. There is no single roadmap doc in the repo — the
plan lives in the "deferred / not implemented" sections scattered across the
design docs. This file collects them in one place, then elaborates the two items
we called out as the strongest next candidates.

> Status: working notes, not a committed design. Fold sections back into
> `docs/*.md` (see the docs map in `AGENTS.md`) when work actually lands.

Last synced: 2026-10-25, after `848ef29` (server-rendered event handlers +
name-significant endpoint routing).

---

## 1. Backlog (gathered from the docs)

### Compiler frontend — `docs/ws-differences.md`
- **Objects / method sends** — `Lsend` is the single unimplemented Lambda
  primitive (`failwith "objects/method sends are not supported yet"`). Interop is
  flattened-function-shaped (`Var.get v`, `Doc.runById id d`). Supporting it means
  (a) lowering `Lsend`, (b) binding interop types as WebSharper classes
  (`[<Prototype>]`) and using `Create`/`setPrototypeOf` for plain/JSON values.
  Pure OCaml `object … end` is explicitly out of scope (own encoding).
  - Related concrete bug: `binding-adaptor` derives instance-ness from a member's
    compiled form, so `[<Macro>]` instance properties (`View.V`/`Var.V`) lose their
    receiver and emit as `unit -> 'a`. (`binding-adaptor/Generator.fs`.)
- **`V` reactive notation** (§2 of the same doc) — not usable; two blockers:
  resolved generic type args are never attached at `ws:` call sites (so *any*
  generic WS macro — `V.v`, `TextView`, `AttrCreate` — fails at `--ws-compile`),
  and the `.V` receiver is dropped. Doc has the proposed `Var.v`/`View.v`
  spelling table.
- **Boundary wire form** — `int32`/`int64`/`nativeint` rejected (no wire
  representation); OCaml objects/classes not representable.

### Endpoint routing — `docs/routing.md` §13, `docs/client-server.md` §7.2
Rejected today with a located diagnostic:
- optional segments (`@page?`), catch-all/rest (`@rest...`), defaults for missing
  query params;
- codec-by-name (`@s:slug`) for user-defined slot types;
- **named record type** payloads (`| User of user`) — only inline records resolve;
- dotted/nested slot names (`@date.y`);
- several `[@endpoint]` aliases per constructor (only the first is read);
- literal query requirements (`?flag`, `?k=v`);
- route-ambiguity detection (first declaration wins; generated `match` warns
  `Warning 11 [redundant-case]`).
- **URL percent-encoding round-trip** — `link` formats raw, router/`parse_query`
  don't decode. ← **candidate A**, §2 below.

Client-side hash routing is **done** (`docs/routing.md` §13):
`WebSharper_UI.Router.installHash` over a `WebSharper_Sitelets.RouterModule`
router (new `websharper-sitelets` binding + `runtimes/ui-server/webSharper_Sitelets.ml`
shadow; `websharper-ui` regenerated with `--reference WebSharper.Sitelets.dll`).
Still missing: `Router.Infer` (a compile-time macro over `[<EndPoint>]`), the
F#-collection/`Func` combinators (`create`, `createWithQuery`, `query*`, `body`,
`fetch`, `xHR`) and real server-side routing through `Router` (the sitelet owns
the URL).

### Templates — `docs/templates.md` §7
- `ws-anchor` parsed but not resolved;
- cross-file instantiation (`ws-file.Tpl`) not implemented (`references = []`);
- **inner templates — done**: the codegen compiles each template (nested ones
  too) to its own `src` + runtime base, because a `<template>` element's content
  is inert at runtime (`parseHTMLIntoFakeRoot` puts it in `.content`, so nested
  lookup fails), and WebSharper.UI's `PrepareTemplateStrict` otherwise puts
  `<template>` DOM nodes into a `HashSet` and `Unchecked.Hash` recurses through
  them (stack overflow). The *server* source additionally keeps the file's
  templates so the native renderer can re-emit them as `ws-children-template`
  placeholders. `ws-template` also had an infinite recursion in `hole.ml`
  (fixed);
- **`.Bind()` / SSR-split — done**: `doc ?keepUnfilled` (server renders the plain
  skeleton) + root `bind` (client `ClientDoc.RunFullDocTemplate` over
  `document.body`). The shadow renders holes / `ws-on*` handler markers /
  `ws-children-template` placeholders like `Runtime.GetOrLoadTemplate`
  (`examples/todomvc-full` exercises the split). Remaining gaps: it is
  all-or-nothing (no per-hole server/client split; the record cannot tell "unset"
  from "default"), and `ws-attr`/`ws-onafterrender` are not reactive (text holes
  have `_view` setters, docs/vars are reactive);
- `ws-dom` and `datetime-local` vars fall back to `string`;
- `ServerLoad`/`ClientLoad` not configurable (source always embedded);
- a template used directly in a server page is static, not hydrated in place
  (reachable once candidate B lands).

### Client/server — `docs/client-server.md` §6
- **node-preserving hydration** (`ws-hole`/`ws-attr-holes` protocol) —
  ← **candidate B**, §3 below;
- `ClientCode`/`IRequiresResources` pipeline and the client-"entry" designation
  are still minimal;
- **RPC marshalling is hand-rolled on the JS side** — `Runtime.js` carries a
  generic `marshalIn`/`marshalOut` driven by an emitted type descriptor, while
  the native tier gets generated `yojson` codecs. This is *not* a substitute for
  WebSharper's built-in JSON: WS's serializer is metadata-driven and we never
  mint `TypeDefinition`s (our values are OCaml-runtime blocks), and the peer is
  native OCaml, so the encoding must exist on both sides regardless (short form
  in `docs/client-server.md` §3.2; full analysis + roadmap in `JSON.md`). The
  smaller design, if worth it: **generate the client codecs too** from the same
  type walk, leaving the descriptor only for the dynamic `[@export]` boundary;
- **external JS libraries (`[<Require>]`/resources)** — a binding to a
  non-WebSharper lib (e.g. Chart.js) lowers to a **global** (`new
  globalThis.Chart(…)`) and needs no bundler, but wsocaml does not honour
  `[<Require>]`/`IResourceDefinition`, so the library's `<script>` is not
  auto-injected into the page — the user adds it via `Content.page ~head`,
  `--static`, or the template. Two directions:
  1. render `[<Require>]`/`IResourceDefinition` resources into the page
     (the .NET-WebSharper behaviour) — needs resource metadata on the binding
     assembly surface (`binding-adaptor`) + a renderer hook in
     `runtimes/ocaml/webSharper_Server.ml`;
  2. support WebSharper `[<Import>]` (emit `import … from "<specifier>"`) —
     a URL specifier then loads natively, a bare one needs an import map/bundler
     (neither is modelled by `binding-adaptor`/`Lowering.fs` today).
  Detail + recipe: `docs/client-bundle.md` §11;
- missing sitelet combinators (`Sum`/`Shift`/`Protect`), `Content.Json` codecs,
  sessions/cookies;
- cross-.NET-server interop would need a position-independent key/serialization
  contract.

### Binding adaptor — `binding-adaptor/README.md` §13
- nested OCaml modules not produced (names are flat/qualified);
- non-public/unrepresentable types degrade to `Js.t`;
- server-only members taking quotations are stubs/omitted;
- cross-assembly compilation relies on the backend minting disjoint numeric ids.

### Suggested order
Do **A first** (small, fixes a correctness bug where `link` can emit a URL its
own router cannot parse). Then **B** (largest single UX gap; unblocks in-place
template hydration too). Objects/`V` notation are deep frontend changes and want
their own design pass.

---

## 2. Candidate A — URL encoding round-trip

### Current behaviour

`fmtArg` emits slot values **raw** (`frontend/bin/main.ml:1129`):

```ocaml
| "int"    -> Printf.sprintf "string_of_int %s" v
| "string" -> v                                      (* ← no encoding *)
| "bool"   -> Printf.sprintf "(if %s then \"true\" else \"false\")" v
| "float"  -> Printf.sprintf "string_of_float %s" v
```

`genLink` (`main.ml:1331`) concatenates those raw values:

```ocaml
| Echo { msg = v0 } -> "/echo/" ^ v0
| Find { q = v0 }   -> "/find" ^ "?" ^ "query=" ^ v0
```

On the way back in, the router splits `req.path` on `/` and matches segments
literally (`genRoute`, `main.ml:1295`), and the server splits the query on
`&`/`=` with **no decoding** (`runtimes/ocaml/webSharper_Server.ml:22`):

```ocaml
let parse_query path =
  ... String.split_on_char '&' q
      |> List.filter_map (fun kv ->
             match String.index_opt kv '=' with
             | Some j -> Some (String.sub kv 0 j, String.sub kv (j+1) (...))
             | None   -> Some (kv, ""))
```

A `percent_decode` **exists** (`webSharper_Server.ml:119`) but is only used by
`serve_file` for **static assets** (`:138`) — the sitelet router never calls it.
`link` and `route` are supposed to be generated from the same plan so they can
never disagree; for `string` slots they currently do.

### What breaks (endpoints from `docs/routing.md` §2 and the site test)

Endpoints:

```ocaml
| Echo of { msg : string } [@endpoint "GET /echo/@msg"]
| Find of { q : string }   [@endpoint "GET /find?query=@q"]
```

| Value | `ctx.link …` emits | Router/server does | Result |
| --- | --- | --- | --- |
| `msg = "a/b"` | `/echo/a/b` | segs `["echo";"a";"b"]` vs pattern `"echo"::v0::[]` | **404** — link's own route doesn't match |
| `msg = "a?b"` | `/echo/a?b` | `parse_query` splits at first `?` → path `/echo/a` | `msg = "a"`, `?b` lost (silent) |
| `msg = "a#b"` | `/echo/a#b` | fragment never reaches the server | `msg = "a"` (silent) |
| `q = "a&b"` | `/find?query=a&b` | pairs `[("query","a");("b","")]` | `q = "a"` (silent truncation) |
| `msg = "a b"` | `/echo/a b`; browser sends `a%20b` | router returns segment `a%20b` undecoded | `msg = "a%20b"` ≠ `"a b"` (reverse broken) |
| `msg = "a%2Fb"` | `/echo/a%2Fb` | passthrough, undecoded | literal `a%2Fb` — indistinguishable from `/` once decoding is added |

Two failure modes: hard **404** (path slots containing `/`, `?`) and **silent
truncation** (query values containing `&`, `#`). The second is the dangerous one —
it never errors, it just routes to the wrong value.

### Fix sketch

1. **Frontend `fmtArg`** (`main.ml:1129`): percent-encode `string` slots,
   context-aware — a `percent_encode` over the RFC 3986 unreserved set
   (`A-Za-z0-9-._~`), encoding everything else. Path slots must encode `/`;
   query slots must additionally encode `&`, `=`, `+`, `#`, `?`. `int`/`bool`
   are already safe; `float` survives (`string_of_float 0.5` = `"0.5"`).
2. **Server decode** — percent-decode in two places:
   - each **path segment** after splitting on `/` (decode *after* the split, so an
     encoded `%2F` is not treated as a separator) — either in the generated router
     or once in `Server.serve`;
   - each **query key and value** in `parse_query`
     (`webSharper_Server.ml:22`), reusing the existing `percent_decode` (`:119`).
   Decide on `+`: either don't treat it specially and encode spaces as `%20`
   (simplest, keep), or decode `+` as space (form semantics).
3. **Keep the bijection honest**: literal path segments in an `[@endpoint …]` are
   literals and are **not** encoded; only `@slot` bindings are.
4. Flip `docs/routing.md` §13 / `client-server.md` §7.2 "URL encoding" from a gap
   to implemented, and add a §-level worked example to `routing.md`.

### Tests to touch
- `backend/tests/apps-site/wssite.ml` — add a route whose `string` slot carries a
  reserved char;
- `runtimes/ocaml/site_client.mjs` — `fetch` the encoded form and assert the
  round-trip (`/echo/a%2Fb` → `Echo:a/b`; `/find?query=a%26b` → `Find:a&b`);
- `backend/tests/site.out` — regenerate with
  `bash backend/tests/run-tests.sh --update`.

---

## 3. Candidate B — node-preserving hydration (`ws-hole`)

### Current behaviour (hydration is client-owned)

`hydrate (fun () -> view)` is compiled two ways (`transformClientServer`,
`main.ml:1458`):
- **server**: `WebSharper_ClientServer.__hydrate "ws<id>" (fun () -> view)`;
- **client**: lifted into `let ws<id> () = Doc.runById "ws<id>" (view)` and
  `registerClient("ws<id>", ws<id>)`.

Server runtime (`runtimes/ocaml/webSharper_ClientServer.ml`):

```ocaml
let region id children = [ Ssr.el "div" [ ("id", id); ("data-ws-key", id) ] children ]
let __hydrate id f = region id (f ())
```

`children` is the **native UI shadow's** eager rendering of the whole view
(`runtimes/ui-server/webSharper_UI.ml` flattens `Doc.t = Ssr.node list` to HTML).
Client runtime (`backend/Runtime.js:295`):

```js
var fn = store[el.getAttribute("data-ws-key")];
if (fn) {
  el.textContent = "";        // ← the region is cleared …
  caml_apply(fn, [0]);        // … then rendered from scratch
  n++;
}
```

So the client **replaces** the server subtree with an identical one. The switch is
visually seamless *only* because the initial markup matches; nothing about the
existing nodes is preserved.

### What is lost

DOM identity for the entire region: `document.activeElement` (focus), text
caret/selection, scroll offsets, in-flight IME composition, native input state the
user typed in the window before the bundle finished loading, `<details open>`
toggles, `<video>/<audio>` playback, and any third-party widget bound to the
original nodes. Plus the cost/jank of replacing the subtree.

Example — server source (using only what the native shadow exports today):

```ocaml
hydrate (fun () ->
  let v = Var.create "before" in

  div [
      on.click (fun _ _ -> Var.set v "after")
  ] [
      textView (Var.view v);
      button [] [ text "click me" ]       (* server-rendered, focusable *)
  ]
)
```

Server HTML (native shadow — note `textView` emits a bare text node, no `<span>`):

```html
<div id="ws204306509" data-ws-key="ws204306509">before<button>click me</button></div>
```

If the bundle takes 400 ms to load, the server markup is already on screen and
interactive. Suppose the user clicks `click me` in that window, so it holds focus
(`document.activeElement`). Then `hydrate()` runs:

```js
region.textContent = "";   // destroys the <button> that currently has focus
```

→ the button is rebuilt from scratch and focus falls back to `<body>`. The same
applies to a text `input` the user has typed into (its node, caret and typed
value are all recreated), to a scrolled list, and to an open `<details>`.

Note on the input case: the native shadow does **not** export the `Html.input`
tag (its `Html` subset is `text`/`textView`/`div`/`span`/`p`/`h1`–`h3`/`ul`/`ol`/
`li`/`b`/`a`/`button`; `runtimes/ui-server/webSharper_UI.ml:108`), so a boundary
example that types into an input needs `DocInputType`/`ClientCheckedInput`
(`:127`, `:136`) or a widening of that subset.

### WebSharper's protocol (what we'd be reimplementing)

On .NET, the server renders the region with **hole markers** around the dynamic
parts, and the client binds *into* the existing nodes instead of replacing them:

- server emits `ws-hole="H"` (view content), `ws-attr-holes="H"` (dynamic attrs),
  `ws-var="V"` (input ↔ `Var`), `ws-replace`, `ws-runafterrender`;
- client `Doc.RunById` walks the existing DOM, finds the holes and binds the
  `Var`/`View` into those parent nodes (adopting their identity);
- static markup is reused wholesale — only the marked dynamic bits are touched.

Note the native **template** shadow already knows this vocabulary:
`runtimes/ui-server/webSharper_UI.ml:299` (`is_marker`) and `:379` (renders
`ws-hole`) — but the `hydrate` path bypasses it: the shadow flattens the eager
`Ssr.node` tree with **no markers**, and `hydrate()` clears first regardless.

Proposed server output for the example above — the dynamic `textView` is now
wrapped in a marker (today the shadow emits it as a bare text node, which cannot
be addressed); the static `<button>` stays unmarked and is adopted wholesale:

```html
<div data-ws-key="ws204306509">
  <span ws-hole="h0">before</span>
  <button>click me</button>
</div>
```

→ the client binds the `View` into the existing `<span>` and leaves the `<button>`
node (and any focus/state on it) untouched. A bound input would carry
`ws-var="v0"`, a dynamic attribute `ws-attr-holes`.

### Fix sketch (why it's the big one)

1. **Shadow `Doc` model.** `Doc.t = Ssr.node list` is eager and has no place to
   carry `EmbedView`/dynamic attributes. Introduce a small reactive `Doc` IR with
   `EmbedView`, `Embed`, `Attr.Dynamic` cases, and a renderer that emits
   `ws-hole`/`ws-attr-holes`/`ws-var` markers for exactly those nodes (a scaled-down
   WebSharper.UI Doc). This is the bulk of the work.
2. **Client adopts, doesn't clear.** Drop the `el.textContent = ""` and bind into
   the existing `ws-hole` nodes — the client binding's `Doc.runById` must run in
   hole mode (WebSharper.UI's templating runtime does this; the *missing half* is
   the server markup contract). Regions with no markers keep today's full-render
   fallback.
3. **Key agreement across tiers.** Hole names must be derived identically in the
   server and client builds from the same source — same class of problem as the
   content-derived event keys (`AGENTS.md` gotcha 11: `Hashtbl.hash` of the
   `Pprintast` text, stable across processes). Reuse that mechanism.
4. Only dynamic parts need markers; static nodes are adopted as-is (the point).

### Tests to touch
- `scripts/ssr-demo.sh`, `backend/tests/apps-ui/wsclient.ml`, `ssr.out` — add a
  case that focuses/types into a node **before** `hydrate()` and asserts
  `document.activeElement` and the typed value survive; assert the region's node
  objects are identical (`===`) before/after.
- `docs/client-server.md` §4 ("future work") and §6 deferred line; the
  `templates.md` §6/§7 in-place-hydration note becomes reachable.

### Smaller interim win
Before clearing, snapshot and restore `input`/`textarea`/`select` state around the
re-render. Fixes the most visible wart (typed text) without the protocol — but
still recreates nodes, so focus/scroll/`open`-state stay lost. Worth it only if B
slips.
