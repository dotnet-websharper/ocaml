# Code generation: from `app.ml` to `server.ml`

A wsocaml program is compiled twice from one source file:

- the **client bundle** (`.wsir.json` → `.js`), and
- the **native server** (a single generated `server.ml`, then `ocamlopt`).

This document explains the second one: exactly which pieces of your source end
up in `server.ml`, how they are printed, and why the result can look quite
different from your file. It complements [`client-server.md`](client-server.md),
which covers the design of the boundary and the sitelet API.

## TL;DR

`server.ml` is **not a copy of your source text**. The frontend parses your
file, rewrites it (sitelet expansion, client-fragment lifting, marker
stripping), then *re-serializes the transformed AST* with the compiler's own
printer (`Pprintast`). So `server.ml` is a generated, reformatted rendering of
the transformed program — semantically faithful to what is compiled, but not
meant to be read or edited. Source locations are preserved separately through
`#` line directives, so diagnostics still point back at your `.ml`.

## 1. Two runs, one pipeline

Both outputs share the same frontend pipeline up to typechecking
(`frontend/bin/main.ml`):

```
parse            -->  transformInfer  -->  transformClientServer  -->  typecheck
                                                                          |
                              +-------------------------------------------+------------------+
                              |                                                              |
                     (default) emit IR /.js/.d.ts                                (--emit-server) emit server.ml
```

- `parse` (`main.ml:299`) reads the file and attaches real locations
  (`Location.init`).
- `transformInfer` (`main.ml:1230`) expands `Sitelet.infer`/`Sitelet.Infer`
  into `Sitelet.make route link handler`, synthesizing the router/URL builder
  from the endpoint variant.
- `transformClientServer` (`main.ml:1299`) lifts `client`/`hydrate` fragments
  into opaque `[@client]` bindings and rewrites `on.<event>` to `On.<event>`.
- `typecheck` runs once on the combined AST.
- `emitServer` (`main.ml:1019`) is what this document is about.

`server.ml` is only produced when the frontend is invoked with `--emit-server`.

## 2. What is selected: `serverItems`

`emitServer` starts from the **transformed** AST and keeps a filtered version of
it, computed by `serverItems ast js` (`main.ml:940`). It walks item by item:

| Source item | Kept in `server.ml`? |
| --- | --- |
| `open WebSharper_UI`, `WebSharper_Server`, `WebSharper_ClientServer` | yes |
| any other `open WebSharper_*` (e.g. `WebSharper_JavaScript`) | **dropped** |
| any other `open` | yes |
| `let[@javascript] f` (client) | **dropped** |
| `let[@export] f` (JS API) | **dropped** |
| `let[@rpc] f` (server, callable from the client) | yes |
| `let f` (server-only) | yes |
| `let[@client] ws<id>` (lifted region) | yes |
| `type`, `module`, `exception`, … | yes |

The exact filter is `js minus clients`: `emitServer` passes
`List.filter (fun n -> not (List.mem n clients)) js`, because `js` (from
`clientMarks`, `main.ml:313`) is the union of `[@javascript]`, `[@export]` and
`[@client]` names. Removing `clients` leaves `[@javascript] ∪ [@export]`, so
`[@client]` bindings survive.

Kept values also have their **marker attributes stripped** (`stripMarkers`,
`main.ml:925`): `javascript`, `rpc`, `export`, `client`, `website` are removed
before printing. The constructors' `[@endpoint …]` attributes were already
removed by `transformInfer`.

### Generated code that is not in your file

After the kept items, `emitServer` appends three things derived from the
program's types and markers:

1. **JSON codecs** — `helperDefs` (`main.ml:733`): `toJson_*`/`ofJson_*`
   functions generated from the `[@rpc]` argument/result types.
2. **RPC registration** — one `Wsrpc.register "<name>" …` per `[@rpc]`
   (`main.ml:1050`), unwrapping an `'a Async.t` handler with `Async.run_sync`
   where needed.
3. **Bootstrap** — `WebSharper_Server.Server.serve ~port ~bundle ~static <sitelet>`
   for a `[@website]` sitelet, or `Wsrpc.serve …` otherwise (`main.ml:1068`).

## 3. How it is printed

`prettyStructure` (`main.ml:994`) does **not** copy source text. For each item
it:

1. emits a `# <line> "<absolute file>"` directive from the item's `pstr_loc`
   (`addLineDirective`, `main.ml:982`), then
2. prints the item with `Pprintast.structure_item` (`printStructureItem`,
   `main.ml:987`).

`Pprintast` is the OCaml compiler's own printer (the one behind `-dsource`). It
re-lays out the AST — indentation, line breaks, parentheses — and drops
everything that is not in the AST. The generated helpers/bootstrap get one
directive pointing at the `[@website]` binding (or at source line 1 when there
is none, `main.ml:1041`).

## 4. Worked example

Source (`examples/hello-world/hello_world.ml`):

```ocaml
type endpoint =
  | Home [@endpoint "GET /"]

let[@website] main =
  Sitelet.infer (fun (_ : endpoint context) ep ->
    match ep with
    | Home ->
        Content.page
          ~title:"Hello, world!"
          [
            h1 [] [text "Hello, world!"];
            hydrate (fun () ->
              let v = Var.create "before" in
              div [ on.click (fun _ _ -> Var.set v "after") ] [
                  textView (Var.view v)
              ]
            )
          ]
  )
```

Generated `server.ml` (abridged):

```ocaml
(* Generated native RPC server. Do not edit. *)
# 2 "/abs/hello_world.ml"
open WebSharper_UI
# 3 "/abs/hello_world.ml"
open WebSharper_UI.Html
# 4 "/abs/hello_world.ml"
open WebSharper_ClientServer
# 5 "/abs/hello_world.ml"
open WebSharper_Server
# 11 "/abs/hello_world.ml"
type endpoint =
  | Home
# 23 "/abs/hello_world.ml"
let ws204306509 () =
  WebSharper_UI.Doc.runById "ws204306509"
    ((fun () ->
        let v = Var.create "before" in
        div [On.click (fun _ _ -> Var.set v "after")] [textView (Var.view v)])
       ())
# 14 "/abs/hello_world.ml"
let main =
  Sitelet.make
    (fun (req : WebSharper_Server.request) -> …generated route…)
    (function | Home -> "/")
    (fun (_ : endpoint context) ep ->
       match ep with
       | Home ->
           Content.page ~title:"Hello, world!"
             [h1 [] [text "Hello, world!"];
             p [] [text "Served by websharper-server, …"];
             WebSharper_ClientServer.__hydrate "ws204306509"
               (fun () ->
                  let v = Var.create "before" in
                  div [On.click (fun _ _ -> Var.set v "after")]
                    [textView (Var.view v)])])
# 14 "/abs/hello_world.ml"

let () =
  WebSharper_Server.Server.serve ~port:8123 ~bundle:"Main" ~static:"/abs/out/client" main
```

Observe:

- `open WebSharper_JavaScript` (source line 1) is gone.
- `Sitelet.infer (fun …)` became `Sitelet.make <route> <link> (fun …)`.
- `hydrate (fun () -> …)` is both replaced by
  `WebSharper_ClientServer.__hydrate "ws204306509" (fun () -> …)` **and** lifted
  into the new `let ws204306509 () = …` binding.
- `on.click` became `On.click`.
- The `[@website]` attribute on `main` is gone.
- The `# <line> "<file>"` lines point each item back at its source line.

## 5. Why the printed code can look different

1. **Reformatting.** `Pprintast` reproduces the AST, not your whitespace: it
   joins/splits lines and re-indents. In the example, `Content.page` and
   `~title:` end up on one line and the list is rewrapped.
2. **Comments are lost.** OCaml comments are not part of the parsetree, so they
   cannot be printed.
3. **Rewrites are already applied.** You see the *expanded* form:
   `Sitelet.infer` → `Sitelet.make route link`; `hydrate`/`client` →
   `__hydrate`/`__client` plus a lifted `ws<id>` binding; `on.x` → `On.x`.
4. **Selection and injection.** Client-only and `[@export]` values and the
   `WebSharper_JavaScript` open are removed; JSON codecs, RPC registration and
   the server bootstrap are added.

None of this changes the program's meaning: `server.ml` is a re-serialization
of the transformed AST, and that transformed AST is exactly what is compiled on
the server.

## 6. Diagnostics and source mapping

Because `server.ml` is generated and compiled from the output directory, two
mechanisms keep errors attached to your source:

- **Native typecheck (`--server-include`).** In `--emit-server` mode the
  frontend typechecks the server-filtered items against the *native* packages
  (`websharper-server`, `websharper-ui-server`) via `typecheckServer`
  (`main.ml:1409`). Server-specific errors — for example a UI combinator the
  server-side `WebSharper_UI` shadow lacks — are reported at the **exact**
  source line/column. `examples/hello-world/build.sh` passes the native
  `--server-include` directories. Warnings are suppressed in this pass because
  the full source was already checked.
- **`#` line directives (fallback).** Anything the typechecker does not catch is
  compiled by `ocamlopt`, which honors the `# <line> "<file>"` directives, so
  such diagnostics still land in your file (see §3).

Together these mean a build failure surfaces on your `.ml`, not on
`server.ml`. For example, replacing `h1` with an element absent from the native
shadow reports:

```
…/hello_world.ml:21:13:15: error: Unbound value h5
```

while a plain type error is reported at the exact expression:

```
…/hello_world.ml:21:25:27: error: The constant 42 has type int but an expression was expected of type string
```

## 7. Guarantees and limits

- **Guaranteed:** `server.ml` parses as valid OCaml and is semantically
  equivalent to the transformed AST; every kept top-level item carries a `#`
  directive back to its source line.
- **Line directives are per top-level item.** Within one item, `Pprintast` may
  use a different number of lines than your source, so a native-compile
  diagnostic that is *not* caught by the typecheck could be off by a few lines.
  Column information is usually still correct.
- **Comments and original formatting are not preserved.** Do not read or edit
  `server.ml`; edit the source.
- **The mapping assumes `Pprintast` round-trips** the AST (it does for the
  constructs the transforms produce). Genuine codegen bugs would show up as
  diagnostics attributed to your source but with no matching code there — a
  signal to look at the generator, not the app.
