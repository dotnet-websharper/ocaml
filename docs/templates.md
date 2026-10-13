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
type t = { vars : vars; mutable title : string; mutable body : string }
val create : unit -> t
val title : string -> t -> t
val body : string -> t -> t
val doc : t -> WebSharper_UI.Doc.t
val references : (string * string * string) list
```

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
> does not support object method sends, so classes cannot be lowered to JS.

## 3. Holes

| Hole | Syntax | OCaml type |
| --- | --- | --- |
| text | `${Name}` in text/attributes | `string` |
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

Event holes get a nominal type from the event name (`click` → `mouse_event`,
`keydown` → `keyboard_event`, `focus`/`blur` → `focus_event`, otherwise
`event`), aliased in `WebSharper_UI.Template`:

```ocaml
(* <button ws-onclick="Remove"> *)
c |> Greeting.remove (fun el ev -> (* ev : WebSharper_UI.Template.mouse_event *) ())
```

Every event also has a `_withModel` variant whose handler receives a record with
access to the instance's `vars` (and, in future, `anchors`):

```ocaml
c
|> Greeting.remove_withModel (fun e ->
     WebSharper_UI.Var.set e.vars.filter "clicked";
     ignore e.target)
```

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

Cyclic template references are rejected (as in WebSharper); express recursion
with a content hole and caller code.

## 5. Editor workflow (VS Code / ocaml-lsp)

The frontend has a `--preprocess` mode that expands `[%template]`. A dune
preprocess action wires it into the editor, so ocaml-lsp sees the generated
module (autocomplete, type errors) and re-runs when the template changes:

```lisp
(preprocess
 (action
  (run bash %{dep:preprocess.sh} %{input-file} %{dep:views/greeting.html})))
```

`preprocess.sh` runs `wsocaml-frontend --preprocess --input <file>`. Add one
`%{dep:…}` per referenced template so dune tracks them.

## 6. Server-side rendering

`WebSharper_UI.Template.getOrLoad` is implemented on both tiers:

- **Client** (`websharper-ui` binding): delegates to
  `WebSharper.UI.Client.Doc.GetOrLoadTemplate` + `DomUtility.ParseHTMLIntoFakeRoot`.
- **Native** (`websharper-ui-server` shadow): a real engine that parses the raw
  source (the shared `websharper-template` parser) and substitutes holes into
  the `Ssr` node tree. DOCTYPE and comments are preserved; events and
  after-render handlers have no server-side effect.

The generated code passes the raw template source as data (structure-as-data),
which is what makes the same module usable on both tiers and leaves room for the
`ServerLoad`/`ClientLoad` modes (embedded source vs. runtime file loading).

## 7. Limitations (current)

- **Record surface, not classes** — see §2.
- **`anchors` are not resolved yet** (`type anchors = unit`). `ws-anchor` is
  parsed, but filling anchor references needs the WebSharper templating runtime
  (`TemplateInstance.Anchor`), which is not bound yet.
- **Cross-file instantiation** (`ws-file.Tpl`) is not implemented; `references`
  is currently `[]`.
- **`ws-dom`** variables and **`datetime-local`** vars fall back to `string`.
- **`ServerLoad`/`ClientLoad`** are not configurable yet; the runtime always
  embeds the source (`Once`/`Inline`).

These are tracked follow-ups; the codegen is structured so adding them does not
change the generated API shape.
