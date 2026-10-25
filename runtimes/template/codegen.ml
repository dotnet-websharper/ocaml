(* Emit an OCaml module (signature + implementation) for a parsed template file.

   Generated surface: a mutable record of holes (`type t`), var getters via a
   `vars` record (fields named after the template's var holes, unprefixed), a
   `doc` terminal, and module-level pipe combinators; inner templates become
   submodules. `_withModel` event setters receive a `TemplateEvent` record with
   access to `vars`/`anchors`.

   (This is a record rather than a class type because the wsocaml IR does not
   support object method sends.)

   Implementation is structure-as-data: it passes the raw template source and
   holes to `WebSharper_UI.Template.getOrLoad`, so one module serves both tiers.
   Anchors and cross-file `references` are placeholders for now. *)

let lcfirst s = if s = "" then s else String.uncapitalize_ascii s

let val_ty_to_string = function
  | Hole.Number -> "float"
  | Hole.Bool -> "bool"
  | Hole.File -> "WebSharper_JavaScript.File.t array"
  | Hole.String | Hole.StringList | Hole.DateTime | Hole.DomElement | Hole.Any -> "string"

(* Event name -> WebSharper.JavaScript event type, from WebSharper's `tags.csv`
   (lowercased names; default `Event`). *)
let event_type_map =
  [ "abort", "UIEvent"; "domactivate", "UIEvent"; "load", "UIEvent"; "resize", "UIEvent";
    "scroll", "UIEvent"; "select", "UIEvent"; "unload", "UIEvent";
    "click", "MouseEvent"; "contextmenu", "MouseEvent"; "dblclick", "MouseEvent";
    "mousedown", "MouseEvent"; "mouseenter", "MouseEvent"; "mouseleave", "MouseEvent";
    "mousemove", "MouseEvent"; "mouseout", "MouseEvent"; "mouseover", "MouseEvent";
    "mouseup", "MouseEvent"; "show", "MouseEvent";
    "keydown", "KeyboardEvent"; "keypress", "KeyboardEvent"; "keyup", "KeyboardEvent";
    "blur", "FocusEvent"; "focus", "FocusEvent";
    "compositionend", "CompositionEvent"; "compositionstart", "CompositionEvent";
    "compositionupdate", "CompositionEvent";
    "domattrmodified", "MutationEvent"; "domcharacterdatamodified", "MutationEvent";
    "domnodeinserted", "MutationEvent"; "domnodeinsertedintodocument", "MutationEvent";
    "domnoderemoved", "MutationEvent"; "domnoderemovedfromdocument", "MutationEvent";
    "domsubtreemodified", "MutationEvent";
    "wheel", "WheelEvent" ]

let event_type name =
  let t =
    match List.assoc_opt (String.lowercase_ascii name) event_type_map with
    | Some a -> a
    | None -> "Event"
  in
  "WebSharper_JavaScript." ^ t ^ ".t"

let element_type = "WebSharper_JavaScript.Element.t"

let ocaml_string s =
  let b = Buffer.create (String.length s + 16) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 32 -> Buffer.add_string b (Printf.sprintf "\\%03d" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let is_var (h : Hole.hole) = match h.Hole.kind with Hole.Var _ -> true | _ -> false
let vars_of (t : Hole.template) = List.filter is_var t.Hole.holes
let non_vars_of (t : Hole.template) = List.filter (fun (h : Hole.hole) -> not (is_var h)) t.Hole.holes

let def_var = function
  | Hole.Number -> "0."
  | Hole.Bool -> "false"
  | Hole.File -> "[||]"
  | _ -> "\"\""

let var_fn = function
  | Hole.Bool -> "WebSharper_UI.TemplateHole.makeVar_2"
  | Hole.Number -> "WebSharper_UI.TemplateHole.makeVar_8"
  | Hole.File -> "WebSharper_UI.TemplateHoleVarFile.create"
  | _ -> "WebSharper_UI.TemplateHole.makeVar"

let event_type_decl (_ : Hole.template) =
  Printf.sprintf
    "type 'e event = { vars : vars; anchors : anchors; target : %s; event : 'e }" element_type

let vars_type (t : Hole.template) =
  let vs = vars_of t in
  if vs = [] then "unit"
  else
    "{ "
    ^ String.concat "; "
        (List.map
           (fun (h : Hole.hole) ->
             match h.Hole.kind with
             | Hole.Var ty -> Printf.sprintf "%s : %s WebSharper_UI.Var.t" (lcfirst h.Hole.name) (val_ty_to_string ty)
             | _ -> "")
           vs)
    ^ " }"

let vars_record (t : Hole.template) =
  let vs = vars_of t in
  if vs = [] then "()"
  else
    "({ "
    ^ String.concat "; "
        (List.map
           (fun (h : Hole.hole) ->
             match h.kind with
             | Hole.Var ty ->
                 Printf.sprintf "%s = WebSharper_UI.Var.create (%s)" (lcfirst h.name) (def_var ty)
             | _ -> "")
           vs)
    ^ " } : vars)"

(* Anchors are not resolved yet (see docs/templates.md). *)
let anchors_type (_ : Hole.template) = "unit"

let anchors_expr (t : Hole.template) =
  if t.anchors = [] then "()"
  else
    "({ "
    ^ String.concat "; "
        (List.map (fun a -> Printf.sprintf "%s = WebSharper_UI.Template.anchor %s" (lcfirst a) (ocaml_string a)) t.anchors)
    ^ " } : anchors)"

(* field declaration for a non-var hole *)
let field_decl (h : Hole.hole) : string =
  let n = lcfirst h.name in
  match h.kind with
  (* Text holes are `View`s so `_view` setters can make them reactive. *)
  | Hole.Simple -> Printf.sprintf "mutable %s : string WebSharper_UI.View.t" n
  | Hole.Doc -> Printf.sprintf "mutable %s : WebSharper_UI.Doc.t" n
  | Hole.Attr -> Printf.sprintf "mutable %s : WebSharper_UI.Attr.t" n
  | Hole.Event ev -> Printf.sprintf "mutable %s : %s -> %s -> unit" n element_type (event_type ev)
  | Hole.ElemHandler -> Printf.sprintf "mutable %s : %s -> unit" n element_type
  | Hole.Var ty -> Printf.sprintf "%s : %s WebSharper_UI.Var.t" n (val_ty_to_string ty)

let field_init (h : Hole.hole) : string =
  let n = lcfirst h.name in
  match h.kind with
  | Hole.Simple -> Printf.sprintf "%s = WebSharper_UI.View.const \"\"" n
  | Hole.Doc -> Printf.sprintf "%s = WebSharper_UI.Doc.empty ()" n
  | Hole.Attr -> Printf.sprintf "%s = WebSharper_UI.Attr.empty ()" n
  | Hole.Event _ -> Printf.sprintf "%s = (fun _ _ -> ())" n
  | Hole.ElemHandler -> Printf.sprintf "%s = (fun _ -> ())" n
  | Hole.Var ty -> Printf.sprintf "%s = WebSharper_UI.Var.create (%s)" n (def_var ty)

let t_type (t : Hole.template) : string =
  let fields = List.map field_decl (non_vars_of t) in
  "type t = { vars : vars; " ^ (if fields = [] then "" else String.concat "; " fields ^ "; ") ^ "}"

let comb_sigs (h : Hole.hole) : string list =
  let n = lcfirst h.name in
  match h.kind with
  | Hole.Simple ->
      [ Printf.sprintf "val %s : string -> t -> t" n;
        Printf.sprintf "val %s_view : string WebSharper_UI.View.t -> t -> t" n ]
  | Hole.Doc -> [ Printf.sprintf "val %s : WebSharper_UI.Doc.t -> t -> t" n ]
  | Hole.Attr -> [ Printf.sprintf "val %s : WebSharper_UI.Attr.t -> t -> t" n ]
  | Hole.Event ev ->
      [ Printf.sprintf "val %s : (%s -> %s -> unit) -> t -> t" n element_type (event_type ev);
        Printf.sprintf "val %s_withModel : (%s event -> unit) -> t -> t" n (event_type ev) ]
  | Hole.ElemHandler -> [ Printf.sprintf "val %s : (%s -> unit) -> t -> t" n element_type ]
  | Hole.Var _ -> []

let rec sig_of ~indent (t : Hole.template) (inner : Hole.template list) : string =
  let pad = String.make indent ' ' in
  let inner_mods =
    List.map
      (fun (sub : Hole.template) ->
        Printf.sprintf "module %s : sig\n%s\n%send" (String.capitalize_ascii (Option.get sub.name))
          (sig_of ~indent:(indent + 2) sub []) pad)
      inner
  in
  let is_root = t.name = None in
  let doc_sig =
    if is_root then "val doc : ?keepUnfilled:bool -> t -> WebSharper_UI.Doc.t"
    else "val doc : t -> WebSharper_UI.Doc.t"
  in
  (* `Bind` is only on the root template (it binds the served document). *)
  let bind_sig = if is_root then [ "val bind : t -> unit" ] else [] in
  let lines =
    [ Printf.sprintf "type vars = %s" (vars_type t);
      Printf.sprintf "type anchors = %s" (anchors_type t);
      event_type_decl t;
      t_type t;
      "val create : unit -> t" ]
    @ List.concat_map comb_sigs t.holes
    @ [ doc_sig ]
    @ bind_sig
    @ inner_mods
    @ [ "val references : (string * string * string) list" ]
  in
  String.concat ("\n" ^ pad) lines

let signature ~base (p : Hole.parsed) : string =
  Printf.sprintf "(* GENERATED from %s.html — do not edit. *)\n\n%s\n" base
    (sig_of ~indent:0 p.root p.inner)

(* --- implementation --------------------------------------------------------- *)

let hole_expr (h : Hole.hole) : string =
  let name = ocaml_string (String.lowercase_ascii h.name) in
  let arg = if is_var h then "c.vars." ^ lcfirst h.name else "c." ^ lcfirst h.name in
  match h.kind with
  | Hole.Simple -> Printf.sprintf "WebSharper_UI.TemplateHole.makeTextView %s %s" name arg
  | Hole.Doc -> Printf.sprintf "WebSharper_UI.TemplateHoleElt.create %s %s" name arg
  | Hole.Attr -> Printf.sprintf "WebSharper_UI.TemplateHoleAttribute.create %s %s" name arg
  | Hole.Event _ ->
      (* `TemplateHoleEvent.create` takes the base `Event.t`; the user's handler
         is typed with the specific event (e.g. `MouseEvent.t`) - downcast. *)
      Printf.sprintf "WebSharper_UI.TemplateHoleEvent.create %s (fun el ev -> %s el (Obj.magic ev))" name arg
  | Hole.ElemHandler -> Printf.sprintf "WebSharper_UI.TemplateHoleAfterRender.create %s %s" name arg
  | Hole.Var ty -> Printf.sprintf "%s %s %s" (var_fn ty) name arg

let is_template_el (el : Markup.element) =
  Markup.find_attr el "ws-template" <> None
  || Markup.find_attr el "ws-children-template" <> None
  || (String.lowercase_ascii el.tag = "template"
      && (Markup.find_attr el "name" <> None || Markup.find_attr el "id" <> None))

(* Serialize each template's own markup and compile it as its own source. Nested
   `<template>` elements in a `[%template]` source are not usable at runtime (their
   content is inert, and looking them up hashes DOM nodes), so the codegen splits
   the one authoring file into per-template sources. *)
let rec strip_templates (nodes : Markup.node list) : Markup.node list =
  List.filter_map
    (fun (nd : Markup.node) ->
      match nd with
      | Markup.Element el when is_template_el el -> None
      | Markup.Element el ->
          Some (Markup.Element { el with Markup.children = strip_templates el.Markup.children })
      | _ -> Some nd)
    nodes

(* A template may be a full HTML document (the official TodoMVC template is);
   render its `<body>` (the served page supplies `<head>`). *)
let rec find_body (nodes : Markup.node list) : Markup.node list option =
  List.find_map
    (fun (nd : Markup.node) ->
      match nd with
      | Markup.Element el when String.lowercase_ascii el.tag = "html" ->
          List.find_map
            (fun (c : Markup.node) ->
              match c with
              | Markup.Element b when String.lowercase_ascii b.tag = "body" -> Some b.Markup.children
              | _ -> None)
            el.Markup.children
      | _ -> None)
    nodes

(* The server source keeps the file's other templates so the native renderer can
   re-emit them as `ws-children-template` placeholders (WS's `writeWrappedTemplate`);
   the client source strips them because the client builds each template from its
   own source (a nested `<template>`'s content is inert in `parseHTMLIntoFakeRoot`). *)
let template_src ~server (t : Hole.template) : string =
  match t.name with
  | None ->
      let body = match find_body t.body with Some ns -> ns | None -> t.body in
      Markup.print (if server then body else strip_templates body)
  | Some _ -> Markup.print t.body

let rec impl_of ~server ~base (t : Hole.template) (inner : Hole.template list) : string =
  let this_base =
    match t.name with None -> base | Some n -> base ^ "-" ^ String.lowercase_ascii n
  in
  let src = ocaml_string (template_src ~server t) in
  let create =
    Printf.sprintf "let create () : t = { vars = %s; %s }"
      (vars_record t)
      (String.concat "; "
         (List.map (fun (h : Hole.hole) -> field_init h) (non_vars_of t)))
  in
  let combinators =
    List.concat_map
      (fun (h : Hole.hole) ->
        let n = lcfirst h.name in
        match h.kind with
        | Hole.Event _ ->
            [ Printf.sprintf "let %s v c = c.%s <- v; c" n n;
              Printf.sprintf
                "let %s_withModel v c = c.%s <- (fun target event -> v { vars = c.vars; anchors = (); target; event }); c"
                n n ]
        | Hole.ElemHandler -> [ Printf.sprintf "let %s v c = c.%s <- v; c" n n ]
        | Hole.Var _ -> []
        | Hole.Simple ->
            [ Printf.sprintf "let %s v c = c.%s <- WebSharper_UI.View.const v; c" n n;
              Printf.sprintf "let %s_view v c = c.%s <- v; c" n n ]
        | _ -> [ Printf.sprintf "let %s v c = c.%s <- v; c" n n ])
      t.holes
  in
  let holes = String.concat ";\n      " (List.map hole_expr t.holes) in
  let is_root = t.name = None in
  (* `?keepUnfilled` is server-side only (it keeps the *unfilled* holes as plain
     `ws-*` / `${…}` markers for the client to fill with `bind`). A fresh instance
     is the usual argument, so with it the codegen passes no holes at all and the
     renderer emits the plain template. *)
  let doc_params = if is_root then "?(keepUnfilled = false) " else "" in
  let doc_ignore = if is_root then "  ignore keepUnfilled;\n" else "" in
  let doc =
    if server then
      let arg =
        if is_root then "(if keepUnfilled then [] else [ " ^ holes ^ " ])"
        else "[ " ^ holes ^ " ]"
      in
      Printf.sprintf
        "let doc %s(c : t) : WebSharper_UI.Doc.t =\n  WebSharper_UI.Template.getOrLoad ~base:%s ~name:(None) ~src ~refs:references ~keep_unfilled:%s\n    %s"
        doc_params (ocaml_string this_base)
        (if is_root then "keepUnfilled" else "false")
        arg
    else
      Printf.sprintf
        "let doc %s(c : t) : WebSharper_UI.Doc.t =\n%s  let fopt = function None -> WebSharper_StdLib.FSharpOption.none () | Some x -> WebSharper_StdLib.FSharpOption.some x in\n  WebSharper_UI.ClientDoc.getOrLoadTemplate %s (fopt (None))\n    (fun () -> WebSharper_UI.DomUtility.parseHTMLIntoFakeRoot src)\n    [ %s ]"
        doc_params doc_ignore (ocaml_string this_base) holes
  in
  (* Root only: bind the served document to this instance's holes (WS's
     `Bind`/`RunFullDocTemplate`). Server-side it is a no-op. *)
  let bind =
    if not is_root then ""
    else if server then "let bind (_ : t) : unit = ()"
    else
      Printf.sprintf
        "let bind (c : t) : unit =\n  ignore (WebSharper_UI.ClientDoc.runFullDocTemplate [ %s ])"
        holes
  in
  let inner_mods =
    List.map
      (fun (sub : Hole.template) ->
        Printf.sprintf "module %s = struct\n%s\nend" (String.capitalize_ascii (Option.get sub.name))
          (impl_of ~server ~base sub []))
      inner
  in
  String.concat "\n"
    ([ Printf.sprintf "type vars = %s" (vars_type t);
       Printf.sprintf "type anchors = %s" (anchors_type t);
       event_type_decl t;
       t_type t;
       Printf.sprintf "let src = %s" src;
       "let references : (string * string * string) list = []";
       create ]
     @ combinators @ [ doc ] @ (if bind = "" then [] else [ bind ]) @ inner_mods)

let implementation ~server ~base ~src (p : Hole.parsed) : string =
  ignore src;
  Printf.sprintf "(* GENERATED from %s.html — do not edit. *)\n\n%s\n" base
    (impl_of ~server ~base p.root p.inner)
