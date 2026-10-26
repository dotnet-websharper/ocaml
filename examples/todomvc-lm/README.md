# TodoMVC (wsocaml) — `ListModel` state

A [TodoMVC](https://todomvc.com/) app written in OCaml with **WebSharper.UI
templates** and a WebSharper.UI **`ListModel`** as its state. It is
[`examples/todomvc-full`](../todomvc-full) with the row state moved from a plain
`todo list` into a keyed, reactive collection:
`views/todomvc.html` is the official
[TodoMVC app template](https://github.com/tastejs/todomvc-app-template) (a full
HTML5 document) with `ws-*`/`${…}` templating attributes added in place. It uses
the WebSharper **SSR split**: the native server renders the template once with
`keepUnfilled` (a skeleton of `ws-*` markers, plus a `ws-children-template`
placeholder for the row) and the client bundle **binds** it to the reactive
state with `TodoPage.bind`. It builds both tiers like
[`examples/hello-world`](../hello-world): a client bundle and a native OCaml
server that serves the page.

Implements the [TodoMVC app spec](https://github.com/tastejs/todomvc/blob/master/app-spec.md):
add (Enter, trimmed, blank ignored, `autofocus`), toggle + **mark all as
complete** (kept in sync), inline **editing** (double-click; Enter/blur commit,
Escape discards, empty destroys; input focused), delete, pluralized **counter**,
**clear completed** (hidden when none), `#main`/`#footer` hidden while empty,
**persistence** to `localStorage["todos-ocaml"]` as
`[{"id","title","completed"}, …]`, and **routing** `#/`, `#/active`,
`#/completed` (restored from the URL; filter links toggle `selected`).

## Files

| File | What |
| --- | --- |
| `todomvc.ml` | model (a `ListModel`) + handlers + the template fills (no markup) |
| `views/todomvc.html` | the official TodoMVC `index.html` (full HTML5 document) + `ws-*`/`${…}` holes |
| `css/app.css` | a compact TodoMVC stylesheet |
| `build.sh` | builds `out/client` (bundle + css) and `out/server` |
| `run.sh` | builds and runs the server on http://127.0.0.1:8123/ |
| `check.sh` | build with single-line diagnostics for the VS Code problem matcher |
| `.vscode/tasks.json` | VS Code `Cmd+Shift+B` build task + "run" task (same as `hello-world`) |
| `dune` | editor/typecheck context (the `websharper-ocaml-ppx` expands `[%template]`) |

Prerequisites are the top-level `README.md` plus `opam install websharper-sitelets`
(used for the hash router; it is a dependency of `websharper-ui`).

## Build & run

Like `examples/hello-world` (prerequisites in the top-level `README.md`):

```sh
bash run.sh        # builds out/{client,server}, then serves :8123
```

or step by step:

```sh
bash build.sh
./out/server &     # http://127.0.0.1:8123/
```

In VS Code, `Cmd+Shift+B` runs the default **wsocaml: build** task (diagnostics
land in the Problems panel), and **wsocaml: run (server on :8123)** — from
*Terminal → Run Task…* — builds and serves the site.

## The state is a `ListModel`

```ocaml
type todos = (int, todo) ListModel.t     (* F# `ListModel<'T,'K>`: OCaml puts the key first *)
let todos = ListModel.create (fun (t : todo) -> t.id) (load ())
...
ListModel.append todos newTodo                                        (* add *)
ListModel.updateBy todos (fun t -> FOpt.some { t with completed = … }) id   (* toggle *)
ListModel.updateAll todos (fun t -> FOpt.some { t with completed = target })  (* mark all *)
ListModel.removeByKey todos id                                        (* delete *)
ListModel.removeBy todos (fun t -> t.completed)                       (* clear completed *)
```

Notes that come out of the generated binding:

- **Keyed.** The key is the `id`, so `updateBy`/`removeByKey` touch exactly one
  row; `updateBy` returning `None` is a no-op (WS's `UpdateBy` only sets), so the
  empty-title destroy uses `removeByKey`.
- **F# `option`.** `ListModel.updateBy`/`updateAll` take `'T -> 'T option` in
  F# terms, i.e. `WebSharper_StdLib.FSharpOption.t` — not OCaml's `option` — so
  the app builds them with `FOpt.some`/`FOpt.none`.
- **Reading the rows.** `ListModel.view`/`map` return an `IEnumerable` which
  these OCaml bindings cannot consume (`IEnumerable` *parameters* are typed as
  OCaml lists), so the reactive rows come from the model's backing
  `Var<array>` (`ListModel.var` → `Var.view` → `View.map`) and the snapshots used
  for persistence/`next id` come from `ListModel.iter`.
- **Persistence** stays typed JSON (`WebSharper_Json.encode`/`decode` on
  `todo list`): WS's own `ListModel.CreateWithStorage` needs a `Serializer<'T>`,
  which wsocaml does not have for OCaml types (`JSON.md`).

## How it fits together

- **Persistence** uses typed JSON: `WebSharper_Json.encode (ts : todo list)` /
  `decode`, so the stored `[{"id","title","completed"}, …]` shape is derived from
  the OCaml type instead of a hand-written encoder (`JSON.md` §1.1).
- **SSR split.** The sitelet renders `TodoPage.doc ~keepUnfilled:true (TodoPage.create ())`
  into `Content.page`, i.e. the template body with every hole left as its plain
  `ws-*` / `${…}` marker and the row re-emitted as a hidden
  `<div ws-children-template="todoItem">`. The client (`let () = …`, dropped from
  `server.ml` because its pattern is not `Ppat_var`) builds the instance, then
  calls `TodoPage.bind inst`, which runs WebSharper's `RunFullDocTemplate` over the
  served `document.body` (see `docs/templates.md`).
- **Reactivity comes from the holes.** `ws-var` holes bind `Var`s; the row list
  (`todos`) and the counter (`count`) are `Doc.bindView`s over a `View.combine`-style
  map of the model's `Var` + the filter/editing `Var`s; the class holes
  (`mainClass`, `allClass`, …) are `*_view` setters backed by `View.map`. The
  new-todo input is focused after the initial bind (`ws-onafterrender`).
- **The template** is the official TodoMVC `index.html` — a **full HTML5
  document** — with `ws-*`/`${…}` holes added in place (the row is a nested
  `<template name="todoItem">` in the `<ul>`). The codegen compiles a
  full-document source to its `<body>` (the served page supplies `<head>`), and
  compiles each template to its own source + base so nested templates from one
  file work.
- **Routing**: `WebSharper_UI.Router.installHash` — a
  `WebSharper_Sitelets.RouterModule.table` router over `#/`, `#/active`,
  `#/completed` gives a reactive `Var<filter>` and intercepts the filter links'
  `#…` `href`s (no hand-rolled `hashchange` listener; the native shadow's
  `installHash` is a no-op because the server owns the URL).

The `dune` project (the editor) checks the app against the **native shadow**
(`runtimes/ui-server/webSharper_UI.ml`, which also mirrors `ListModel`), while
the build uses the generated client binding (`websharper-ui`) — which is why it
sticks to the surface the two have in common (`Doc`/`View`/`Var`/`ListModel`).
`open WebSharper_UI` also shadows `WebSharper_JavaScript.Storage`/`Array`/`Attr`/
`Notation`, so the DOM calls are aliased (`module JsStorage = …` — the top-level
README's *Name collisions and shadowing* explains why the editor and the build
can disagree about a bare name).

This example drove three upstream fixes: `WebSharper_UI.ListModel` in the native
shadow; `--emit-server`'s typecheck now keeps the client include dirs next to the
native ones (a top-level alias into a client-only package such as
`WebSharper_StdLib` could not resolve); and a bare top-level module *alias* no
longer shifts the `[@rpc]`/`[@client]` module-block indices (it shares the
aliased module's slot, which misbound the hydrated region on load).
