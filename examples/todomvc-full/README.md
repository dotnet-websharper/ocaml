# TodoMVC (wsocaml)

A [TodoMVC](https://todomvc.com/) app written in OCaml with **WebSharper.UI
templates**: `views/todomvc.html` is the official
[TodoMVC app template](https://github.com/tastejs/todomvc-app-template) (a full
HTML5 document) with `ws-*`/`${…}` templating attributes added in place. It uses
the WebSharper **SSR split**: the native server renders the template once with
`keepUnfilled` (a skeleton of `ws-*` markers, plus a `ws-children-template`
placeholder for the row) and the client bundle **binds** it to the reactive
state with `Tmpl.bind`. It builds both tiers like
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

## How it fits together

- **SSR split.** The sitelet renders `Tmpl.doc ~keepUnfilled:true (Tmpl.create ())`
  into `Content.page`, i.e. the template body with every hole left as its plain
  `ws-*` / `${…}` marker and the row re-emitted as a hidden
  `<div ws-children-template="todoItem">`. The client (`let () = …`, dropped from
  `server.ml` because its pattern is not `Ppat_var`) builds the instance, then
  calls `Tmpl.bind inst`, which runs WebSharper's `RunFullDocTemplate` over the
  served `document.body` (see `docs/templates.md`).
- **Reactivity comes from the holes.** `ws-var` holes bind `Var`s; the row list
  (`todos`) and the counter (`count`) are `Doc.bindView`s over the state; the
  class holes (`mainClass`, `allClass`, …) are `*_view` setters backed by
  `View.map`, so only the affected parts re-render on a state change. The
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

The app also typechecks against the **native shadow**
(`runtimes/ui-server/webSharper_UI.ml`), which is why it sticks to the shadow's
`Doc`/`View`/`Var` surface. This example drove several compiler/runtime changes:
`?keepUnfilled`/`bind` and `*_view` text holes in `runtimes/template/codegen.ml`;
plain-marker / handler-marker / sub-template-placeholder rendering
(`keep_unfilled`, `ws-on*`, `ws-children-template`) in the shadow; the missing
`caml_string_*` primitives in `backend/Runtime.js`; and `Doc.concat`/`Doc.bindView`
in the shadow.
