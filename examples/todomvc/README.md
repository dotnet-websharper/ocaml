# TodoMVC (wsocaml)

A [TodoMVC](https://todomvc.com/) app written in OCaml with **WebSharper.UI
templates**: `views/todomvc.html` is the official
[TodoMVC app template](https://github.com/tastejs/todomvc-app-template) (a full
HTML5 document) with `ws-*`/`${…}` templating attributes added in place, and
`todomvc.ml` fills its holes. It builds both tiers like
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
| `todomvc.ml` | model + handlers + the template fills (no markup) |
| `views/todomvc.html` | the official TodoMVC `index.html` (full HTML5 document) + `ws-*`/`${…}` holes |
| `css/app.css` | a compact TodoMVC stylesheet |
| `build.sh` | builds `out/client` (bundle + css) and `out/server` |
| `run.sh` | builds and runs the server on http://127.0.0.1:8123/ |
| `check.sh` | build with single-line diagnostics for the VS Code problem matcher |
| `.vscode/tasks.json` | VS Code `Cmd+Shift+B` build task + "run" task (same as `hello-world`) |
| `dune` | editor/typecheck context (the `websharper-ocaml-ppx` expands `[%template]`) |

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

## How it fits together

- **Persistence** uses typed JSON: `WebSharper_Json.encode (ts : todo list)` /
  `decode`, so the stored `[{"id","title","completed"}, …]` shape is derived from
  the OCaml type instead of a hand-written encoder (`JSON.md` §1.1).
- **Client-only app.** Everything lives in one top-level `let ()`. Such a binding
  is *dropped* from `server.ml` (its pattern is not `Ppat_var`), so the app runs
  only in the client bundle. The build typechecks it against the generated client
  binding (`websharper-ui`), while the `dune` project (`dune build`, the editor)
  checks the **native shadow** (`runtimes/ui-server/webSharper_UI.ml`) — which is
  why the app sticks to the surface the two have in common (`Doc`/`View`/`Var`).
- **Opens and shadowing.** `open WebSharper_UI` re-exports a `Storage` of its own
  (`WebSharper.UI.Storage`), hiding `WebSharper_JavaScript.Storage`; the DOM calls
  are aliased (`module JsStorage = WebSharper_JavaScript.Storage`) rather than
  fully qualified everywhere. See the top-level README's *Name collisions and
  shadowing* for the full list (`Storage`/`Array`/`Attr`/`Notation`, and why the
  editor and the build can disagree).
- **The server** is a one-route sitelet that serves the shell
  (`<div id="root"></div>` + the bundle + `/css/app.css`); the client bundle
  renders the app into `#root` with `Doc.runById`.
- **The template** is the official TodoMVC `index.html` — a **full HTML5
  document** — with `ws-*`/`${…}` holes added in place (the row is a nested
  `<template name="todoItem">` in the `<ul>`). The codegen compiles a
  full-document source to its `<body>` for rendering (the served page supplies
  `<head>`), and compiles each template to its own source (a `<template>`'s
  content is inert at runtime). The page is a `Doc.bindView` over the state, so it
  re-renders on change; the new-todo input is re-focused after each render
  (`ws-onafterrender`).
- **Routing**: the filter links' `href` plus a `Window` `hashchange` listener
  (the listener body is sequenced, not a tail call — a bare tail call compiles to
  a trampoline thunk a raw DOM listener never drives).

This example also drove several compiler/runtime fixes: the missing
`caml_string_*` primitives in `backend/Runtime.js`; `Doc.concat`/`Doc.bindView`
in the `WebSharper_UI` shadow; and `runtimes/template/codegen.ml` now compiles
each template (including nested ones) to its own source + base, so nested
templates from one file work at runtime.
