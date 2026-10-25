(* Native, server-side subset of WebSharper.UI for server-side rendering.

   The same view source compiles against the generated `WebSharper_UI` binding
   for the client and against this module for the server; the server renders the
   initial HTML (with `[@client]` regions) and the client hydrates it. Only the
   combinators used by the views are provided here. *)

module View = struct
  type 'a t = { get : unit -> 'a }

  let get t = t.get ()
  let map f t = { get = (fun () -> f (get t)) }
  let map2 f a b = { get = (fun () -> f (get a) (get b)) }
  let map3 f a b c = { get = (fun () -> f (get a) (get b) (get c)) }
  let const x = { get = (fun () -> x) }

  (* The server renders once; `Sink` registers a client-side reaction, so here it
     just observes the current value. *)
  let sink f t = f (get t)
end

module Var = struct
  type 'a t = { mutable v : 'a }

  let create x = { v = x }
  let get t = t.v
  let set t x = t.v <- x
  let update t f = t.v <- f t.v
  let view t = { View.get = (fun () -> t.v) }
end

module Attr = struct
  type t = string * string

  let create k v = (k, v)
  let empty () = ("", "")
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
  let empty () : t = []
  let textView (v : string View.t) = [ Ssr.text (View.get v) ]
  let concat (ds : t list) : t = List.concat ds
  (* The server renders the current value once; the client binding re-renders. *)
  let bindView (f : 'a -> t) (v : 'a View.t) : t = f (View.get v)
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

(* Input constructors (`WebSharper.UI.Client.Doc+InputType`). Server-side rendering
   emits the initial input markup; the client hydrates/interacts. *)
module ClientCheckedInput = struct
  type 'a t = { ctext : string }
  let make (_ : 'a) : 'a t = { ctext = "" }
  let newInvalid (s : string) : 'a t = { ctext = s }
  let newBlank (s : string) : 'a t = { ctext = s }
  let newValid (_ : 'a) (s : string) : 'a t = { ctext = s }
  let input (t : 'a t) = t.ctext
end

module DocInputType = struct
  type t = Doc.t

  let el_input typ (attrs : Attr.t list) (value : string option) : Doc.t =
    let attrs = List.filter (fun (k, _) -> k <> "") attrs in
    let attrs = ("type", typ) :: attrs in
    let attrs = match value with Some v -> ("value", v) :: attrs | None -> attrs in
    [ Ssr.el "input" attrs [] ]

  let str typ attrs (v : string Var.t) = el_input typ attrs (Some (Var.get v))
  let strV typ attrs v = el_input typ attrs (Some v)
  let ints typ attrs (v : int Var.t) = el_input typ attrs (Some (string_of_int (Var.get v)))
  let intsV typ attrs v = el_input typ attrs (Some (string_of_int v))
  let floats typ attrs (v : float Var.t) = el_input typ attrs (Some (Printf.sprintf "%g" (Var.get v)))
  let floatsV typ attrs v = el_input typ attrs (Some (Printf.sprintf "%g" v))

  let text attrs v = str "text" attrs v
  let password attrs v = str "password" attrs v
  let color attrs v = str "color" attrs v
  let date attrs v = str "date" attrs v
  let email attrs v = str "email" attrs v
  let month attrs v = str "month" attrs v
  let search attrs v = str "search" attrs v
  let tel attrs v = str "tel" attrs v
  let time attrs v = str "time" attrs v
  let url attrs v = str "url" attrs v
  let week attrs v = str "week" attrs v
  let textV attrs v = strV "text" attrs v
  let passwordV attrs v = strV "password" attrs v
  let colorV attrs v = strV "color" attrs v
  let dateV attrs v = strV "date" attrs v
  let emailV attrs v = strV "email" attrs v
  let monthV attrs v = strV "month" attrs v
  let searchV attrs v = strV "search" attrs v
  let telV attrs v = strV "tel" attrs v
  let timeV attrs v = strV "time" attrs v
  let urlV attrs v = strV "url" attrs v
  let weekV attrs v = strV "week" attrs v

  let dateTimeLocal attrs (_ : WebSharper_StdLib.DateTime.t Var.t) =
    el_input "datetime-local" attrs None
  let dateTimeLocalV attrs (_ : WebSharper_StdLib.DateTime.t) =
    el_input "datetime-local" attrs None

  let intUnchecked attrs v = ints "number" attrs v
  let intUncheckedV attrs v = intsV "number" attrs v
  let range attrs v = ints "range" attrs v
  let rangeV attrs v = intsV "range" attrs v
  let floatUnchecked attrs v = floats "number" attrs v
  let floatUncheckedV attrs v = floatsV "number" attrs v

  let int attrs (v : int ClientCheckedInput.t Var.t) =
    el_input "number" attrs (Some (ClientCheckedInput.input (Var.get v)))
  let intV attrs (v : int ClientCheckedInput.t) =
    el_input "number" attrs (Some (ClientCheckedInput.input v))
  let float attrs (v : float ClientCheckedInput.t Var.t) =
    el_input "number" attrs (Some (ClientCheckedInput.input (Var.get v)))
  let floatV attrs (v : float ClientCheckedInput.t) =
    el_input "number" attrs (Some (ClientCheckedInput.input v))

  let file attrs (_ : WebSharper_JavaScript.File.t array Var.t) = el_input "file" attrs None
  let fileV attrs (_ : WebSharper_JavaScript.File.t array) = el_input "file" attrs None

  let textArea attrs (v : string Var.t) =
    [ Ssr.el "textarea" (List.filter (fun (k, _) -> k <> "") attrs) [ Ssr.text (Var.get v) ] ]
  let textAreaV attrs v =
    [ Ssr.el "textarea" (List.filter (fun (k, _) -> k <> "") attrs) [ Ssr.text v ] ]

  let checkBox attrs (v : bool Var.t) =
    let attrs =
      List.filter (fun (k, _) -> k <> "") attrs @ [ ("type", "checkbox") ]
      @ (if Var.get v then [ ("checked", "") ] else [])
    in
    [ Ssr.el "input" attrs [] ]

  let checkBoxGroup (_ : Attr.t list) (_ : 'a) (_ : 'a WebSharper_StdLib.FSharpList.t Var.t) : Doc.t =
    [ Ssr.el "div" [] [] ]
  let radio (_ : Attr.t list) (_ : 'a) (_ : 'a Var.t) : Doc.t = el_input "radio" [] None
  let select (_ : Attr.t list) (_ : 'a -> string) (_ : 'a WebSharper_StdLib.FSharpList.t) (_ : 'a Var.t) : Doc.t =
    [ Ssr.el "select" [] [] ]
  let selectDyn (_ : Attr.t list) (_ : 'a -> string) (_ : 'a WebSharper_StdLib.FSharpList.t View.t) (_ : 'a Var.t) : Doc.t =
    [ Ssr.el "select" [] [] ]
  let selectMultiple (_ : Attr.t list) (_ : 'a -> string)
      (_ : 'a WebSharper_StdLib.FSharpList.t) (_ : 'a WebSharper_StdLib.FSharpList.t Var.t) : Doc.t =
    [ Ssr.el "select" [ ("multiple", "") ] [] ]
  let selectMultipleDyn (_ : Attr.t list) (_ : 'a -> string)
      (_ : 'a WebSharper_StdLib.FSharpList.t View.t) (_ : 'a WebSharper_StdLib.FSharpList.t Var.t) : Doc.t =
    [ Ssr.el "select" [ ("multiple", "") ] [] ]
  let selectOptional (_ : Attr.t list) (_ : string) (_ : 'a -> string)
      (_ : 'a WebSharper_StdLib.FSharpList.t) (_ : 'a WebSharper_StdLib.FSharpOption.t Var.t) : Doc.t =
    [ Ssr.el "select" [] [] ]
  let selectDynOptional (_ : Attr.t list) (_ : string) (_ : 'a -> string)
      (_ : 'a WebSharper_StdLib.FSharpList.t View.t) (_ : 'a WebSharper_StdLib.FSharpOption.t Var.t) : Doc.t =
    [ Ssr.el "select" [] [] ]
end

module EltInputType = DocInputType

(* WebSharper.UI.Notation: typed `Var` operators (`!` deref, `:=` set, `<~` modify). *)
module Notation = struct
  let ( ! ) (v : 'a Var.t) : 'a = Var.get v
  let ( := ) (v : 'a Var.t) (x : 'a) : unit = Var.set v x
  let ( <~ ) (v : 'a Var.t) (f : 'a -> 'a) : unit = Var.set v (f (Var.get v))
end

(* WebSharper.UI.Router (hash routing) is client-only: on the server the sitelet
   owns the URL, so the router value is never consulted and `installHash` just
   yields a `Var` holding the default. The surface mirrors the client binding so
   that shared source typechecks on both tiers. *)
module Router = struct
  let installHash (default : 'a) (_ : 'a WebSharper_Sitelets.Router2.t) : 'a Var.t =
    Var.create default

  let installHashInto (v : 'a Var.t) (default : 'a) (_ : 'a WebSharper_Sitelets.Router2.t) : unit =
    Var.set v default

  let install (default : 'a) (_ : 'a WebSharper_Sitelets.Router2.t) : 'a Var.t = Var.create default

  let installInto (v : 'a Var.t) (default : 'a) (_ : 'a WebSharper_Sitelets.Router2.t) : unit =
    Var.set v default

  let linkHash (r : 'a WebSharper_Sitelets.Router2.t) (v : 'a) : string =
    WebSharper_Sitelets.RouterModule.hashLink r v

  let getCurrentHash (_ : string -> 'a option) (default : 'a) : 'a = default
end

module RouterExtensions = struct
  let installHash (r : 'a WebSharper_Sitelets.Router2.t) (default : 'a) : 'a Var.t =
    Router.installHash default r

  let install (r : 'a WebSharper_Sitelets.Router2.t) (default : 'a) : 'a Var.t =
    Router.install default r

  let linkHash (r : 'a WebSharper_Sitelets.Router2.t) (v : 'a) : string =
    Router.linkHash r v
end

(* Server-side template engine. The generated code builds `TemplateHole` values
   (mirroring the WebSharper.UI client API) and calls `Template.getOrLoad`; we
   parse the raw source (shared parser) and substitute the holes into the SSR
   node tree. Events and after-render handlers have no server-side effect. *)

module TemplateHole = struct
  type value =
    | VText of string
    | VElt of Doc.t
    | VAttr of Attr.t
    | VEvent
    | VAfterRender
    | VVarStr of string Var.t
    | VVarBool of bool Var.t
    | VVarFloat of float Var.t
    | VVarFile

  type t = { thname : string; thvalue : value }

  let makeText name v = { thname = name; thvalue = VText v }
  let makeTextView name (v : string View.t) = { thname = name; thvalue = VText (View.get v) }
  let makeVar name v = { thname = name; thvalue = VVarStr v }
  let makeVar_2 name v = { thname = name; thvalue = VVarBool v }
  let makeVar_8 name v = { thname = name; thvalue = VVarFloat v }
end

module TemplateHoleElt = struct
  type t = TemplateHole.t
  let create name (v : Doc.t) = { TemplateHole.thname = name; thvalue = TemplateHole.VElt v }
end

module TemplateHoleAttribute = struct
  type t = TemplateHole.t
  let create name (v : Attr.t) = { TemplateHole.thname = name; thvalue = TemplateHole.VAttr v }
end

module TemplateHoleEvent = struct
  type t = TemplateHole.t
  let create name (_ : WebSharper_JavaScript.Element.t -> WebSharper_JavaScript.Event.t -> unit) =
    { TemplateHole.thname = name; thvalue = TemplateHole.VEvent }
end

module TemplateHoleAfterRender = struct
  type t = TemplateHole.t
  let create name (_ : WebSharper_JavaScript.Element.t -> unit) =
    { TemplateHole.thname = name; thvalue = TemplateHole.VAfterRender }
end

module TemplateHoleVarFile = struct
  type t = TemplateHole.t
  let create name (_ : WebSharper_JavaScript.File.t array Var.t) =
    { TemplateHole.thname = name; thvalue = TemplateHole.VVarFile }
end

module Template = struct
  let starts_with pre s =
    String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

  let is_marker kl =
    kl = "ws-hole" || kl = "ws-replace" || kl = "ws-attr" || kl = "ws-var" || kl = "ws-dom"
    || kl = "ws-onafterrender" || starts_with "ws-on" kl
    || kl = "data-hole" || kl = "data-replace" || kl = "data-attr" || kl = "data-var"
    || kl = "data-var-unchecked" || starts_with "data-event-" kl

  (* A template definition: the element is itself a sub-template (`ws-template`),
     its children are (`ws-children-template`), or it is an HTML5 `<template>`
     with a `name`/`id`. These are detached from the body and re-emitted as
     `ws-children-template` placeholders (see `getOrLoad`). *)
  let is_template_el (el : Markup.element) =
    Markup.find_attr el "ws-template" <> None
    || Markup.find_attr el "ws-children-template" <> None
    || (String.lowercase_ascii el.tag = "template"
        && (Markup.find_attr el "name" <> None || Markup.find_attr el "id" <> None))

  let hole_string (v : TemplateHole.value) : string =
    match v with
    | TemplateHole.VText s -> s
    | TemplateHole.VVarStr v -> Var.get v
    | TemplateHole.VVarBool v -> if Var.get v then "true" else "false"
    | TemplateHole.VVarFloat v -> Printf.sprintf "%g" (Var.get v)
    | TemplateHole.VElt _ | TemplateHole.VAttr _ | TemplateHole.VEvent | TemplateHole.VAfterRender
    | TemplateHole.VVarFile -> ""

  let find (tbl : (string, TemplateHole.t) Hashtbl.t) (name : string) =
    Hashtbl.find_opt tbl (String.lowercase_ascii name)

  (* Replace `${Name}` occurrences using the filled holes. With [keep_unfilled]
     an unfilled hole is left as its plain `${Name}` marker (for the client). *)
  let subst tbl ~keep_unfilled (s : string) : string =
    let n = String.length s in
    let b = Buffer.create n in
    let i = ref 0 in
    while !i < n do
      if !i < n - 1 && s.[!i] = '$' && s.[!i + 1] = '{' then begin
        let j = ref (!i + 2) in
        while !j < n && s.[!j] <> '}' do incr j done;
        if !j < n then begin
          let name = String.sub s (!i + 2) (!j - !i - 2) in
          (match find tbl name with
           | Some h -> Buffer.add_string b (hole_string h.TemplateHole.thvalue)
           | None -> if keep_unfilled then Buffer.add_string b ("${" ^ name ^ "}"));
          i := !j + 1
        end
        else (Buffer.add_char b s.[!i]; incr i)
      end
      else (Buffer.add_char b s.[!i]; incr i)
    done;
    Buffer.contents b

  (* A filled event / after-render hole has no server-side behaviour, so it is
     always written back as its `ws-on<event>` / `ws-onafterrender` marker and
     the client attaches the handler (WS's `Attr.ServerHandler`). *)
  let is_handler_hole tbl name =
    match find tbl name with
    | Some { TemplateHole.thvalue = TemplateHole.VEvent; _ }
    | Some { TemplateHole.thvalue = TemplateHole.VAfterRender; _ } -> true
    | _ -> false

  (* One attribute of a rendered element (the `ws-hole` / `ws-replace` markers
     are handled on the element itself). *)
  let attr tbl ~keep_unfilled (k, v) : (string * string) option =
    let kl = String.lowercase_ascii k in
    if kl = "ws-hole" || kl = "ws-replace" then None
    else if kl = "ws-attr" then (
      match find tbl v with
      | Some { TemplateHole.thvalue = TemplateHole.VAttr (ak, av); _ } -> Some (ak, av)
      | _ -> if keep_unfilled then Some (k, v) else None)
    else if kl = "ws-var" then (
      match find tbl v with
      | Some h -> Some ("value", hole_string h.TemplateHole.thvalue)
      | None -> if keep_unfilled then Some (k, v) else None)
    else if kl = "ws-onafterrender" || starts_with "ws-on" kl then
      if keep_unfilled || is_handler_hole tbl v then Some (k, v) else None
    else if is_marker kl then None
    else Some (k, subst tbl ~keep_unfilled v)

  let rec render_nodes tbl ~keep_unfilled nodes = List.concat_map (render_node tbl ~keep_unfilled) nodes

  and render_node tbl ~keep_unfilled (node : Markup.node) : Doc.t =
    match node with
    | Markup.Text s -> [ Ssr.text (subst tbl ~keep_unfilled s) ]
    | Markup.Comment c -> [ Ssr.comment c ]
    | Markup.Doctype d -> [ Ssr.doctype d ]
    (* Sub-template definitions are not content; they are re-emitted as
       placeholders at the end of the root render. *)
    | Markup.Element el when is_template_el el -> []
    | Markup.Element el -> render_element tbl ~keep_unfilled el

  and render_element tbl ~keep_unfilled (el : Markup.element) : Doc.t =
    match Markup.find_attr el "ws-replace" with
    | Some name0 -> (
        match find tbl name0 with
        | Some { TemplateHole.thvalue = TemplateHole.VElt d; _ } -> d
        | _ -> if keep_unfilled then [ Ssr.el el.tag [ ("ws-replace", name0) ] [] ] else [])
    | None ->
        let ws_hole = Markup.find_attr el "ws-hole" in
        let attrs = List.filter_map (attr tbl ~keep_unfilled) el.attrs in
        let attrs =
          match ws_hole with
          | Some name0 when keep_unfilled -> ("ws-hole", name0) :: attrs
          | _ -> attrs
        in
        let children =
          match ws_hole with
          | Some name0 -> (
              match find tbl name0 with
              | Some { TemplateHole.thvalue = TemplateHole.VElt d; _ } -> d
              | _ -> [])
          | None -> render_nodes tbl ~keep_unfilled el.children
        in
        [ Ssr.el el.tag attrs children ]

  (* A sub-template placeholder (`<div style="display:none" ws-children-template="name">`
     wrapping the template body written in plain mode), as WS's `writeWrappedTemplate`
     emits for every other template of the file under `<body>`. *)
  let placeholder name (t : Hole.template) : Doc.t =
    let plain : (string, TemplateHole.t) Hashtbl.t = Hashtbl.create 1 in
    let body = render_nodes plain ~keep_unfilled:true t.Hole.body in
    [ Ssr.el "div" [ ("style", "display:none"); ("ws-children-template", name) ] body ]

  let getOrLoad ~base ~name ~src ~refs ~keep_unfilled (holes : TemplateHole.t list) : Doc.t =
    ignore base; ignore refs;
    let parsed = Hole.analyze (Markup.parse src) in
    let tbl : (string, TemplateHole.t) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun (h : TemplateHole.t) -> Hashtbl.replace tbl (String.lowercase_ascii h.thname) h) holes;
    match name with
    | None ->
        (* The root render carries the other templates of the file as
           `ws-children-template` placeholders (WS appends them under `<body>`). *)
        let body = render_nodes tbl ~keep_unfilled parsed.Hole.root.Hole.body in
        let extra =
          List.filter_map
            (fun (t : Hole.template) -> Option.map (fun n -> placeholder n t) t.Hole.name)
            parsed.Hole.inner
        in
        body @ List.concat extra
    | Some n -> (
        match List.find_opt (fun (t : Hole.template) -> t.name = Some n) parsed.Hole.inner with
        | Some t -> render_nodes tbl ~keep_unfilled t.Hole.body
        | None -> render_nodes tbl ~keep_unfilled parsed.Hole.root.Hole.body)
end
