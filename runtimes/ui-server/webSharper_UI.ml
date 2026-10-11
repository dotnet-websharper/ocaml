(* Native, server-side subset of WebSharper.UI for server-side rendering.

   The same view source compiles against the generated `WebSharper_UI` binding
   for the client and against this module for the server; the server renders the
   initial HTML (with `[@client]` regions) and the client hydrates it. Only the
   combinators used by the views are provided here. *)

module View = struct
  type 'a t = { get : unit -> 'a }

  let get t = t.get ()
  let map f t = { get = (fun () -> f (get t)) }
  let const x = { get = (fun () -> x) }
end

module Var = struct
  type 'a t = { mutable v : 'a }

  let create x = { v = x }
  let get t = t.v
  let set t x = t.v <- x
  let view t = { View.get = (fun () -> t.v) }
end

module Attr = struct
  type t = string * string

  let create k v = (k, v)
end

module On = struct
  (* Event handlers have no server-side effect. *)
  let click (_ : 'a -> 'b -> unit) : Attr.t = ("", "")
end

(* IDE-facing shim: the wsocaml compiler rewrites `on.<event>` to `On.<event>`,
   but a stock OCaml toolchain (Merlin/ocaml-lsp) sees `on.click` as a field
   access, so `on` is provided here so source typechecks editor-side. *)
type event
type on_handlers = {
  click : (event -> event -> unit) -> Attr.t;
  dblclick : (event -> event -> unit) -> Attr.t;
  change : (event -> event -> unit) -> Attr.t;
  input : (event -> event -> unit) -> Attr.t;
  keydown : (event -> event -> unit) -> Attr.t;
  keyup : (event -> event -> unit) -> Attr.t;
  submit : (event -> event -> unit) -> Attr.t;
}

let _on_noop (_ : event -> event -> unit) : Attr.t = ("", "")

let on =
  {
    click = _on_noop;
    dblclick = _on_noop;
    change = _on_noop;
    input = _on_noop;
    keydown = _on_noop;
    keyup = _on_noop;
    submit = _on_noop;
  }

module Doc = struct
  type t = Ssr.node list

  let text s = [ Ssr.text s ]
  let empty : t = []
  let textView (v : string View.t) = [ Ssr.text (View.get v) ]
  let render (d : t) = String.concat "" (List.map Ssr.render_node d)

  (* On the server, `runById` renders the doc into a region. *)
  let runById id (d : t) =
    Ssr.regions_replace id (String.concat "" (List.map Ssr.render_node d))
end

let el name (attrs : Attr.t list) (children : Doc.t list) : Doc.t =
  [ Ssr.el name (List.filter (fun (k, _) -> k <> "") attrs) (List.concat children) ]

let div = el "div"
let span = el "span"
let p = el "p"
let h1 = el "h1"
let h2 = el "h2"
let h3 = el "h3"
let h4 = el "h4"
let ul = el "ul"
let ol = el "ol"
let li = el "li"
let b = el "b"
let i = el "i"
let a = el "a"
let em = el "em"
let strong = el "strong"
let button = el "button"
let label = el "label"
let section = el "section"
let header = el "header"
let footer = el "footer"
let form = el "form"
let input = el "input"
let table = el "table"
let tr = el "tr"
let td = el "td"
let th = el "th"

module Html = struct
  let text = Doc.text
  let textView = Doc.textView
  let div = div
  let span = span
  let p = p
  let h1 = h1
  let h2 = h2
  let h3 = h3
  let ul = ul
  let ol = ol
  let li = li
  let b = b
  let a = a
  let button = button
end
