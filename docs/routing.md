# Endpoint routing by example

`Sitelet.infer` compiles the `[@endpoint …]` attributes of the endpoint variant
into a router and a URL builder:

```ocaml
route : request -> endpoint option   (* parse a request *)
link  : endpoint -> string           (* build a URL *)
```

Both are generated from the same plan (`endpointPlan` / `genRoute` / `genLink`,
`frontend/bin/main.ml`), so a route parses exactly what its `link` produces and
the two can never disagree.

Every example below comes from one app, compiled with `--emit-server`. The
`route`/`link` snippets are that app's generated `server.ml` (abridged: the
printer fully parenthesizes every operation), the requests and responses are the
actual served output. The site test (`backend/tests/apps-site/wssite.ml`,
`frontend/test: site`) covers a subset of these end to end.

## The app

```ocaml
open WebSharper_Server

type endpoint =
  | Root     [@endpoint "GET /"]
  | Echo     of string                        [@endpoint "GET /echo/@0"]
  | Add      of int * int                     [@endpoint "GET /add/@0/@1"]
  | Swap     of int * string                  [@endpoint "GET /swap/@1/@0"]
  | Item     of { id : int; slug : string }   [@endpoint "GET /item/@slug/@id"]
  | Flags    of { on : bool; ratio : float }  [@endpoint "GET /flags/@on/@ratio"]
  | UserPost of { id : int; slug : string }   [@endpoint "GET /user/@id/post/@slug"]
  | Posts    of { tag : string; page : int }  [@endpoint "GET /posts/@tag?page=@page"]
  | Find     of { q : string }                [@endpoint "GET /find?query=@q"]
  | Create   of { name : string }             [@endpoint "POST /create/@name"]

let[@website] main =
  Sitelet.infer (fun (ctx : endpoint context) ep ->
    match ep with
    | Root -> Content.text (Printf.sprintf "Root | link=%s" (ctx.link (Echo "hi")))
    | Echo s -> Content.text (Printf.sprintf "Echo(%s) | link=%s" s (ctx.link (Echo s)))
    | Add (a, b) -> Content.text (Printf.sprintf "Add(%d,%d) | link=%s" a b (ctx.link (Add (a, b))))
    | Swap (n, s) -> Content.text (Printf.sprintf "Swap(%d,%s) | link=%s" n s (ctx.link (Swap (n, s))))
    | Item i -> Content.text (Printf.sprintf "Item(%s,%d) | link=%s" i.slug i.id (ctx.link (Item i)))
    | Flags f -> Content.text (Printf.sprintf "Flags(%b,%.1f) | link=%s" f.on f.ratio (ctx.link (Flags f)))
    | UserPost u -> Content.text (Printf.sprintf "UserPost(%d,%s) | link=%s" u.id u.slug (ctx.link (UserPost u)))
    | Posts p -> Content.text (Printf.sprintf "Posts(%s,%d) | link=%s" p.tag p.page (ctx.link (Posts p)))
    | Find f -> Content.text (Printf.sprintf "Find(%s) | link=%s" f.q (ctx.link (Find f)))
    | Create c -> Content.text (Printf.sprintf "Create(%s) | link=%s" c.name (ctx.link (Create c))))
```

## At a glance

| Scenario | `[@endpoint …]` | Request | Value | `ctx.link` |
| --- | --- | --- | --- | --- |
| constant | `GET /` | `GET /` | `Root` | `/` |
| one positional arg | `GET /echo/@0` | `GET /echo/hi` | `Echo "hi"` | `/echo/hi` |
| positional, in order | `GET /add/@0/@1` | `GET /add/3/4` | `Add (3, 4)` | `/add/3/4` |
| positional, reordered | `GET /swap/@1/@0` | `GET /swap/abc/7` | `Swap (7, "abc")` | `/swap/abc/7` |
| record, reordered | `GET /item/@slug/@id` | `GET /item/abc/7` | `Item { id = 7; slug = "abc" }` | `/item/abc/7` |
| record, `bool` + `float` | `GET /flags/@on/@ratio` | `GET /flags/true/0.5` | `Flags { on = true; ratio = 0.5 }` | `/flags/true/0.5` |
| record + literal segment | `GET /user/@id/post/@slug` | `GET /user/9/post/hello` | `UserPost { id = 9; slug = "hello" }` | `/user/9/post/hello` |
| path + query | `GET /posts/@tag?page=@page` | `GET /posts/fsharp?page=3` | `Posts { tag = "fsharp"; page = 3 }` | `/posts/fsharp?page=3` |
| query key ≠ field | `GET /find?query=@q` | `GET /find?query=ocaml` | `Find { q = "ocaml" }` | `/find?query=ocaml` |
| non-GET method | `POST /create/@name` | `POST /create/thing` | `Create { name = "thing" }` | `/create/thing` |

## 1. Constant constructor — no payload

```ocaml
| Root [@endpoint "GET /"]
```

```ocaml
(* route *) | ("GET", []) -> (try Some Root with | _ -> None)
(* link  *) | Root -> "/"
```

The first argument to `Sitelet.make` (the route) receives the whole request;
the second (the link) the value. `link` never includes the method — a URL is the
same for every method.

## 2. One positional argument — `@0`

```ocaml
| Echo of string [@endpoint "GET /echo/@0"]
```

```ocaml
(* route *) | ("GET", "echo"::v0::[]) -> (try Some (Echo v0) with | _ -> None)
(* link  *) | Echo v0 -> "/echo/" ^ v0
```

A **tuple payload** is positional: its slots are named by **argument index**
(`@0`, `@1`, …), so a single-argument constructor uses `@0`. (For a readable
name, use an inline record instead — see §5.)

## 3. Several positional arguments, in order — `@0`, `@1`

```ocaml
| Add of int * int [@endpoint "GET /add/@0/@1"]
```

```ocaml
(* route *) | ("GET", "add"::v0::v1::[]) -> (try Some (Add (int_of_string v0, int_of_string v1)) with | _ -> None)
(* link  *) | Add (v0, v1) -> "/add/" ^ string_of_int v0 ^ "/" ^ string_of_int v1
```

The index in `@i` **is** the argument index, and the codec comes from that
argument's type (`int_of_string` on the way in, `string_of_int` on the way out).

## 4. Several positional arguments, reordered — the URL order is free

```ocaml
| Swap of int * string [@endpoint "GET /swap/@1/@0"]
```

```ocaml
(* route *) | ("GET", "swap"::v0::v1::[]) -> (try Some (Swap (int_of_string v1, v0)) with | _ -> None)
(* link  *) | Swap (v0, v1) -> "/swap/" ^ v1 ^ "/" ^ string_of_int v0
```

`@1` comes first in the endpoint string, so the first URL segment is argument 1
(the `string`) and the second is argument 0 (the `int`):

```text
GET /swap/abc/7   ->  Swap (7, "abc")     (* not /swap/7/abc *)
```

## 5. Inline record, one or more fields — `@name` is a field name

```ocaml
| Item of { id : int; slug : string } [@endpoint "GET /item/@slug/@id"]
```

```ocaml
(* route *) | ("GET", "item"::v0::v1::[]) -> (try Some (Item { id = int_of_string v1; slug = v0 }) with | _ -> None)
(* link  *) | Item { id = v0; slug = v1 } -> "/item/" ^ v1 ^ "/" ^ string_of_int v0
```

Each `@name` must be a field of the payload, and the URL order is the order you
write them in — here `slug` before `id`, the reverse of the declaration. Swapping
the two names in the endpoint string swaps the URL, and the field's type still
picks the codec:

```ocaml
| Item of { id : int; slug : string } [@endpoint "GET /item/@id/@slug"]
(* route *) ... -> Some (Item { id = int_of_string v0; slug = v1 })
(* link  *) | Item { id = v0; slug = v1 } -> "/item/" ^ string_of_int v0 ^ "/" ^ v1
```

## 6. Non-string payload types — `bool`, `float`

```ocaml
| Flags of { on : bool; ratio : float } [@endpoint "GET /flags/@on/@ratio"]
```

```ocaml
(* route *) ... -> (try Some (Flags { on = (v0 = "true"); ratio = float_of_string v1 }) with | _ -> None)
(* link  *) | Flags { on = v0; ratio = v1 } -> "/flags/" ^ (if v0 then "true" else "false") ^ "/" ^ string_of_float v1
```

| Slot type | URL -> value (route) | value -> URL (link) |
| --- | --- | --- |
| `int` | `int_of_string` | `string_of_int` |
| `string` | identity | identity |
| `bool` | `= "true"` (anything else is `false`) | `"true"` / `"false"` |
| `float` | `float_of_string` | `string_of_float` |

Any other slot type is a compile error (see §12).

## 7. Literal path segments mixed with bindings

```ocaml
| UserPost of { id : int; slug : string } [@endpoint "GET /user/@id/post/@slug"]
```

```ocaml
(* route *) | ("GET", "user"::v0::"post"::v1::[]) -> (try Some (UserPost { id = int_of_string v0; slug = v1 }) with | _ -> None)
(* link  *) | UserPost { id = v0; slug = v1 } -> "/user/" ^ string_of_int v0 ^ "/post/" ^ v1
```

Segments that don't start with `@` match literally (`"post"::_`), so literals and
bindings can be interleaved freely.

## 8. Path + query parameters

```ocaml
| Posts of { tag : string; page : int } [@endpoint "GET /posts/@tag?page=@page"]
```

```ocaml
(* route *)
| ("GET", "posts"::v0::[]) ->
    (try Some (Posts { tag = v0; page = int_of_string (Stdlib.List.assoc "page" req.query) })
     with | _ -> None)
(* link *)
| Posts { tag = v0; page = v1 } -> "/posts/" ^ v0 ^ "?page=" ^ string_of_int v1
```

The route reads the query from `req.query` (`(string * string) list`, parsed by
the server). A **missing** parameter raises `Not_found`, which the surrounding
`try … with _ -> None` turns into "no match" → `404`:

```text
GET /posts/fsharp          ->  404 not found   (* page is required *)
```

## 9. Several query parameters

```ocaml
| Search of { q : string; page : int } [@endpoint "GET /search?q=@q&page=@page"]
```

```ocaml
(* route *)
| ("GET", "search"::[]) ->
    (try Some (Search { q = Stdlib.List.assoc "q" req.query;
                        page = int_of_string (Stdlib.List.assoc "page" req.query) })
     with | _ -> None)
(* link *)
| Search { q = v0; page = v1 } -> "/search?q=" ^ v0 ^ "&page=" ^ string_of_int v1
```

Both the key (`q`) and the slot (`@q`) are significant; the link emits the keys
in the order they are written.

## 10. Query key different from the field name

```ocaml
| Find of { q : string } [@endpoint "GET /find?query=@q"]
```

```ocaml
(* route *) | ("GET", "find"::[]) -> (try Some (Find { q = Stdlib.List.assoc "query" req.query }) with | _ -> None)
(* link  *) | Find { q = v0 } -> "/find?query=" ^ v0
```

The left side of `=` is the URL key, the right side (after `@`) is the payload
slot. Every query item must have the `key=@name` shape — a bare `flag` or a
literal `?k=v` is a compile error (see §12).

## 11. Non-GET methods

```ocaml
| Create of { name : string } [@endpoint "POST /create/@name"]
```

```ocaml
(* route *) | ("POST", "create"::v0::[]) -> (try Some (Create { name = v0 }) with | _ -> None)
(* link  *) | Create { name = v0 } -> "/create/" ^ v0
```

The method (before the first space; `GET` when omitted) is matched by the route
and ignored by the link:

```text
POST /create/thing  ->  200 Create(thing) | link=/create/thing
GET  /create/thing  ->  404 not found
```

## 12. Order freedom, bijection, and diagnostics

The `@names` of one endpoint must be a **bijection** over its payload slots:
every `@name` must name a slot, and every slot must be bound exactly once. The
URL order is free; the binding is checked before any code is generated, and
every diagnostic points at the constructor:

```text
User of { id : int; name : string } [@endpoint "GET /user/@idd/@name"]
  error: the endpoint 'User' has no field 'idd' (fields: id, name)

User of { id : int; name : string } [@endpoint "GET /user/@id/@id"]
  error: the endpoint 'User' binds 'id' twice

User of { id : int; name : string } [@endpoint "GET /user/@id"]
  error: the endpoint 'User' does not bind its field 'name' (add '@name' to the path or query)

Move of int * string [@endpoint "PUT /move/@from/@to"]
  error: the endpoint 'Move' has no argument 'from' (use '@0' or '@1')

Move of int [@endpoint "GET /move/@1"]
  error: the endpoint 'Move' has no argument '1' (use '@0')

Plain [@endpoint "GET /plain/@x"]     (* no payload at all *)
  error: the endpoint 'Plain' has no argument 'x' (it takes no arguments)

Search of { q : string } [@endpoint "GET /search?flag"]
  error: unsupported query item 'flag' in the endpoint 'Search' (use 'key=@name')

Search of { q : int list } [@endpoint "GET /search?q=@q"]
  error: unsupported type 'int list' for field 'q' of 'Search' (use int, string, bool or float)

Posts of { tag : string; page : int } [@endpoint "GET /posts/@tag/@page?"]
  error: the endpoint 'Posts' has an empty query part (write 'key=@name'; optional segments like '@page?' are not supported)

Echo of string                       (* no [@endpoint] at all *)
  error: the endpoint constructor 'Echo' has no [@endpoint "METHOD /path"] attribute
```

These are the `backend/tests/errors/*.ml` goldens, normalized by
`frontend/bin/diag.exe` to `file:line:col:col: severity: message` for the editor
problem matcher.

## 13. Client-side hash routing — `Router.installHash`

Everything above is **server-side** routing (URL → the `[@endpoint]` DU, and
`ctx.link` back). For **client-side** routing on the URL fragment,
`WebSharper.UI.Router.installHash` is bound: build a router with the
`WebSharper_Sitelets.RouterModule` combinators, then install it as a reactive
`Var`:

```ocaml
type filter = All | Active | Completed

(* #/   #/active   #/completed *)
let filter_router : filter WebSharper_Sitelets.Router.t =
  WebSharper_Sitelets.RouterModule.table
    [ (All, ""); (Active, "active"); (Completed, "completed") ]

let filter_var : filter Var.t =
  WebSharper_UI.Router.installHash All filter_router
```

- `Router.installHash default router : 'a Var.t` reads the current hash, listens
  to `hashchange`/`popstate`, intercepts clicks on `#…` anchors
  (`preventDefault`), and pushes `Router.HashLink` when the `Var` changes.
- `RouterModule.table [ (v, "path") ]` is one way to build a router; the binding
  also has `fromString`, `single`, `shift`, `sum`, `map`, `filter`, `delay`,
  `link`, `hashLink`, `tryLink`, `parse`, `write`, `cast`. A `Link` requires that
  a route consumes the whole path, so `""` (the bare `#/`) only matches the empty
  hash — that is why `All` is listed first.
- On the **native server** there is no URL, so the `websharper-ui-server` shadow's
  `Router.installHash` is a no-op returning `Var.create default`; its
  `WebSharper_Sitelets` implements the same combinators (and the router
  representation is pure OCaml), so one source typechecks on both tiers.

`examples/todomvc-full` uses this for its `#/`, `#/active`, `#/completed` filter,
with the links written as plain `<a href="#/…">`.

The pieces: the generated `websharper-sitelets` binding
(`binding-adaptor gen WebSharper.Sitelets.dll`, referred to by the regenerated
`websharper-ui`), `runtimes/ui-server/webSharper_Sitelets.ml` (shadow), and
`-I $(ocamlfind query websharper-sitelets)` + `--reference
WebSharper.Sitelets.dll` in `scripts/build-ui-app.sh`.

## 14. What is not implemented yet

These are **rejected** today (a variant of the diagnostics above), not silently
accepted:

| Scenario | Would look like | Status |
| --- | --- | --- |
| optional segment | `GET /posts/@tag/@page?` | rejected — the `?` starts an empty query part (see §12) |
| catch-all / rest segment | `GET /files/@dir/@rest...` | rejected (`'rest...'` is not a field name) |
| codec by name | `GET /post/@s:slug` | rejected (`'s:slug'` is not a field name) |
| named record type payload | `\| User of user` (a `type user = { … }`) | rejected — only inline records resolve |
| nested / dotted slot name | `GET /log/@date.y/@date.m` | rejected (`'date.y'` is not a field name) |
| several `[@endpoint]` aliases on one constructor | two attributes | only the first is read |
| literal query requirement | `GET /list?flag` or `?k=v` | rejected (must be `key=@name`) |
| default for a missing query parameter | — | a missing parameter is a non-match (404) |
| route ambiguity detection | two constructors matching `GET /` | first declaration wins (the generated `match` warns `redundant-case`) |

Two more gaps that affect routing:

- **URL encoding**: `link` formats slot values raw and the server's query parser
  doesn't decode, so values containing `/`, `&`, `?` or spaces don't round-trip.
- **Query-only endpoints** (`[@endpoint "GET /?q=@q"]`) work, but a constant
  `[@endpoint "GET /"]` declared earlier matches `GET /` first — put the more
  specific path (e.g. `GET /lookup?q=@q`) in front, or give it a path segment.

## Regenerating these examples

Save the app above as `app.ml` (from the same directory, next to nothing else),
then — after `dune build` in `frontend/` — emit the native server and read the
`Sitelet.make` call it prints:

```sh
# the client-facing server API stubs, as scripts/site-demo.sh builds them
mkdir -p out/cmi
cp runtimes/server-api/webSharper_Server.mli runtimes/server-api/webSharper_ClientServer.mli out/cmi/
( cd out/cmi && ocamlc -c webSharper_Server.mli -I "$(ocamlfind query websharper-ui)" \
    -I "$(ocamlc -where)" && ocamlc -c webSharper_ClientServer.mli \
    -I "$(ocamlfind query websharper-ui)" -I "$(ocamlc -where)" )

frontend/_build/default/bin/main.exe --input app.ml --emit-server server.ml \
  --unit Main --static out/client -I out/cmi \
  -I "$(ocamlfind query websharper-ui)" -I "$(ocamlfind query websharper-javascript)" \
  -I "$(ocamlfind query websharper-runtime)" -I "$(ocamlfind query websharper-stdlib)" \
  -I "$(ocamlc -where)"
```

The router is the first argument of the generated `Sitelet.make`, the URL builder
the second; both are printed from the same plan.

To run it, link `server.ml` with the runtimes the way `scripts/site-demo.sh`
does and `curl` the routes above.
