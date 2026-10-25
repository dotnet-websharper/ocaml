# Templates

wsocaml supports WebSharper.UI-style templates: an `.html` file with `${…}` and
`ws-*` (or legacy `data-*`) holes is compiled into a typed OCaml module you fill
from code. The same generated module works on both tiers — the client binding
and the native server — and server-side rendering (SSR) of the initial markup is
supported.

This document covers authoring, the generated API, the editor workflow, and the
current limitations.

## 1. Declaring a template

Reference a template file from code with `[%template "path"]` (the path is
resolved relative to the declaring source file):

```ocaml
open WebSharper_UI

(* views/greeting.html → module Greeting *)
module Greeting = [%template "views/greeting.html"]
```

The frontend expands this before typechecking into a generated module; it is not
a runtime call. Generated code carries `#` line directives back to the
`[%template]` site, so diagnostics stay in your source.

### `views/greeting.html`

```html
<div class="greeting">
  <!-- rendered by WebSharper_UI.Template -->
  <h1>${Title}</h1>
  <p>${Body}</p>
</div>
```

## 2. The generated API

For the template above, `Greeting` exposes a mutable record of holes, a `doc`
terminal, and pipe combinators:

```ocaml
type vars = unit
type anchors = unit
type 'e event = { vars : vars; anchors : anchors; target : WebSharper_UI.Template.element; event : 'e }
type t = { vars : vars; mutable title : string WebSharper_UI.View.t;
                            mutable body : string WebSharper_UI.View.t }
val create : unit -> t
val title : string -> t -> t
val title_view : string WebSharper_UI.View.t -> t -> t
val body : string -> t -> t
val body_view : string WebSharper_UI.View.t -> t -> t
val doc : ?keepUnfilled:bool -> t -> WebSharper_UI.Doc.t   (* root template *)
val bind : t -> unit                                        (* root template *)
val references : (string * string * string) list
```

- **Text holes are `View`s** (`title : string View.t`): the plain setter wraps the
  string in `View.const`, and a `<name>_view` setter takes a `View<string>` so the
  value can be reactive (the client rebuilds the attribute/text on change).
- **`doc ?keepUnfilled`** is server-side only. `keepUnfilled:true` renders the
  plain template — every hole left as its marker — for the client to fill (§6).
- **`bind`** is on the **root** template only: it binds the served document to the
  instance (WebSharper's `Bind`/`RunFullDocTemplate`); server-side it is `()`.
  Sub-template modules get `doc` but no `bind`/`?keepUnfilled`.

### Usage

```ocaml
let g =
  Greeting.create ()
  |> Greeting.title "Hello, world!"
  |> Greeting.body "Rendered from a template."

(* server-side rendering *)
Ssr.render_nodes (Greeting.doc g)

(* or, in a sitelet page *)
Content.page ~title:"Hello" [ Greeting.doc g ]
```

> The surface is a **record with pipe combinators**, not a class: the wsocaml IR
> does not support object method sends, so classes cannot be lowered to JS. It
> mirrors WebSharper's *runtime* (`ProviderBuilder` / `Runtime.GetOrLoadTemplate`
> / `CompletedHoles` / `Builder.BindBody`), not its method sugar.

## 3. Holes

| Hole | Syntax | OCaml type |
| --- | --- | --- |
| text | `${Name}` in text/attributes | `string` (+ `_view : string WebSharper_UI.View.t`) |
| doc (content) | `ws-hole="Name"` | `WebSharper_UI.Doc.t` |
| doc (replace) | `ws-replace="Name"` | `WebSharper_UI.Doc.t` |
| attribute | `ws-attr="Name"` | `WebSharper_UI.Attr.t` |
| event | `ws-on<event>="Name"` | `element -> <event-type> -> unit` |
| after-render | `ws-onafterrender="Name"` | `element -> unit` |
| variable | `ws-var="Name"` (on an input) | `<ty> WebSharper_UI.Var.t` |

Legacy `data-*` attributes are recognized too: `data-hole`, `data-replace`,
`data-attr`, `data-var`, `data-var-unchecked`, `data-event-<event>` (and the
legacy `$!{Name}` text syntax).

### Variable types

`ws-var` infers the type from the element: `<textarea>` → `string`,
`<select multiple>` → `string`, `<input type=checkbox>` → `bool`,
`<input type=number|range>` → `float`, `<input type=file>` →
`WebSharper_UI.Template.file array`, otherwise `string`. Variables are exposed
in the `vars` record under their template name (unprefixed):

```ocaml
(* <input ws-var="Filter"> *)
c.vars.filter           (* : string WebSharper_UI.Var.t *)
WebSharper_UI.Var.set c.vars.filter "abc"
```

### Events

Event holes get a **nominal** type from the event name (`click` →
`WebSharper_JavaScript.MouseEvent.t`, `keydown` → `KeyboardEvent.t`,
`focus`/`blur` → `FocusEvent.t`, `wheel` → `WheelEvent.t`, otherwise `Event.t`),
per WebSharper's `tags.csv`:

```ocaml
(* <button ws-onclick="Remove"> *)
c |> Card.remove (fun el ev -> (* ev : WebSharper_JavaScript.MouseEvent.t *)
     Console.log (string_of_int (MouseEvent.button ev)))
```

Event types are abstract; upcast to a base explicitly (the equivalent of F#’s
`:>`):

```ocaml
let ev : WebSharper_JavaScript.MouseEvent.t = ... in
let e : WebSharper_JavaScript.Event.t = MouseEvent.as_event ev in
Event.stopPropagation e
```

Each event also has a `_withModel` variant whose handler receives a record with
access to the instance's `vars`:

```ocaml
c
|> Greeting.remove_withModel (fun e ->
     WebSharper_UI.Var.set e.vars.filter "clicked";
     ignore e.target)
```

(DOM *node* types — `Element`, `Node`, `Document` — remain collapsed to the
single abstract `EventTarget.t`, so no coercions are needed between them.)

> The `ws-on<event>` attribute family is shared with server-rendered handlers:
> for a template the value names a **hole** (resolved from the template's hole
> table), whereas the compiler emits `ws-on<event>="<key>"` for an `on.<event>`
> handler on a server-rendered element, and the client runtime attaches only
> values that are registered keys. See `docs/client-server.md` §4.1.

### Anchors

`ws-anchor="Name"` is parsed but **anchors are not resolved yet** (the `anchors`
record is `unit`); see §7.

## 4. Inner templates

`ws-template`, `ws-children-template`, and `<template name="…">` define named
sub-templates; they become **submodules**:

```html
<ul>
  <template name="Row">
    <li><span>${Name}</span></li>
  </template>
</ul>
```

```ocaml
Greeting.Row.create () |> Greeting.Row.name "a" |> Greeting.Row.doc
```

The codegen gives every template its own `src` string (its own markup) and its
own runtime base name, so a single `.html` with several `<template name="…">` (or
`ws-template` / `ws-children-template`) works. This is necessary because a
`<template>` element's content is *inert* at runtime (parsed into `.content`,
invisible to `querySelectorAll`), and WebSharper.UI's nested-template lookup
otherwise hashes DOM nodes structurally (`Unchecked.Hash`) and overflows the
stack.

The **client** source strips the sub-template definitions (each template is built
from its own source), but the **server** source keeps them, because the native
renderer re-emits every other template of the file as a
`<div style="display:none" ws-children-template="name">…</div>` placeholder at the
end of the root render (WebSharper's `writeWrappedTemplate`) — that is what lets a
client `.Bind()` find the sub-templates in the served document.

A template whose source is a **full HTML document** (e.g. the official TodoMVC
`index.html`, `<!doctype html><html>…`) is compiled to its `<body>` for rendering;
the served page supplies `<head>` (styles, scripts).

Cyclic template references are rejected (as in WebSharper); express recursion
with a content hole and caller code.

## 5. Editor workflow (VS Code / ocaml-lsp)

Add the template ppx to the editor's dune library:

```lisp
(preprocess (pps websharper-ocaml-ppx))
```

Dune forwards `pps` preprocessors to merlin, so ocaml-lsp expands `[%template]`
and you get autocomplete/type errors on the generated module. (Dune does *not*
forward custom `(preprocess (action …))` to merlin, which is why a ppx is used;
it shares the frontend's `Codegen`.)

Install it once with `opam install ./frontend` (provides `websharper-ocaml-ppx`).
The real build (`build.sh`) does not use the ppx — the frontend expands
`[%template]` itself while also tracking the template as a dependency.

## 6. Server-side rendering

The generated holes are the WebSharper.UI client API (`WebSharper_UI.TemplateHole*`,
`WebSharper_UI.ClientDoc.GetOrLoadTemplate`, `WebSharper_UI.DomUtility`), so the
client bundle uses the real WebSharper.UI template runtime (its macros resolve
because the generated module is part of the entry unit).

The **native server** provides the same surface in the `webSharper_UI` shadow: a
`TemplateHole` mirror plus `Template.getOrLoad`, a real engine that parses the
raw source (the shared `websharper-template` parser) and renders it into the
`Ssr` node tree. DOCTYPE and comments are preserved. `--emit-server` generates the
server form of `doc` (shadow call); the client build generates the client form
(`ClientDoc` + `WebSharper_StdLib.FSharpOption`).

The renderer mirrors WebSharper's `Runtime.GetOrLoadTemplate`:

- a **filled** text/doc/attr/var hole is substituted (`value="…"`, the doc's
  nodes, …);
- a **filled event / after-render** hole is written back as its
  `ws-on<event>` / `ws-onafterrender` marker (it has no server-side effect; the
  client attaches the handler — WebSharper's `Attr.ServerHandler`);
- every other template of the file is re-emitted as a
  `ws-children-template` placeholder (see §4).

With **`doc ~keepUnfilled:true`** (and no holes, i.e. a fresh instance) every hole
is left as its plain `${…}` / `ws-hole` / `ws-replace` / `ws-attr` / `ws-var`
marker, so the served page is a skeleton the client fills. The **`bind`** terminal
then runs WebSharper's `RunFullDocTemplate` over `document.body` — this is the
SSR split used by `examples/todomvc-full`:

```ocaml
(* server *)
Content.page [ Tmpl.doc ~keepUnfilled:true (Tmpl.create ()) ]

(* client *)
let inst = Tmpl.create () |> Tmpl.todos (Doc.bindView view …) |> … in
Tmpl.bind inst
```

> `keepUnfilled` keeps only the *unfilled* holes; the codegen passes no holes for
> it, so on a fresh instance the whole template is plain. Filled event handlers
> are markers regardless (see above).
>
> A template used directly in a sitelet page **without** `bind` is static markup
> and is not interactive on the client; wrap it in `hydrate`/`client` for
> interactivity, or use the `keepUnfilled` + `bind` split above.

The generated code passes the raw template source as data (structure-as-data),
which is what makes the same module usable on both tiers and leaves room for the
`ServerLoad`/`ClientLoad` modes.

## 7. Limitations (current)

- **Record surface, not classes** — see §2.
- **Anchors** (`ws-anchor`) are parsed but not resolved yet.
- **Cross-file instantiation** (`ws-file.Tpl`) is not implemented; `references`
  is currently `[]`.
- **`ws-dom`** variables and **`datetime-local`** vars fall back to `string`.
- **`ServerLoad`/`ClientLoad`** are not configurable yet; the runtime always
  embeds the source (`Once`/`Inline`).
- **`bind` / `keepUnfilled` is all-or-nothing**: the record cannot tell "unset"
  from "set to the default", so `doc ~keepUnfilled:true` passes no holes and the
  whole template is rendered plain (a skeleton). Per-hole server/client splits
  would need set-tracking.
- **Reactive holes are text (`*_view`), docs and vars**; `ws-attr` and
  `ws-onafterrender` are not reactive yet.

These are tracked follow-ups; the codegen is structured so adding them does not
change the generated API shape.
