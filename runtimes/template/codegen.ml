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
  | Hole.Simple -> Printf.sprintf "mutable %s : string" n
  | Hole.Doc -> Printf.sprintf "mutable %s : WebSharper_UI.Doc.t" n
  | Hole.Attr -> Printf.sprintf "mutable %s : WebSharper_UI.Attr.t" n
  | Hole.Event ev -> Printf.sprintf "mutable %s : %s -> %s -> unit" n element_type (event_type ev)
  | Hole.ElemHandler -> Printf.sprintf "mutable %s : %s -> unit" n element_type
  | Hole.Var ty -> Printf.sprintf "%s : %s WebSharper_UI.Var.t" n (val_ty_to_string ty)

let field_init (h : Hole.hole) : string =
  let n = lcfirst h.name in
  match h.kind with
  | Hole.Simple -> Printf.sprintf "%s = \"\"" n
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
  | Hole.Simple -> [ Printf.sprintf "val %s : string -> t -> t" n ]
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
  let lines =
    [ Printf.sprintf "type vars = %s" (vars_type t);
      Printf.sprintf "type anchors = %s" (anchors_type t);
      event_type_decl t;
      t_type t;
      "val create : unit -> t" ]
    @ List.concat_map comb_sigs t.holes
    @ [ "val doc : t -> WebSharper_UI.Doc.t" ]
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
  | Hole.Simple -> Printf.sprintf "WebSharper_UI.TemplateHole.makeText %s %s" name arg
  | Hole.Doc -> Printf.sprintf "WebSharper_UI.TemplateHoleElt.create %s %s" name arg
  | Hole.Attr -> Printf.sprintf "WebSharper_UI.TemplateHoleAttribute.create %s %s" name arg
  | Hole.Event _ ->
      (* `TemplateHoleEvent.create` takes the base `Event.t`; the user's handler
         is typed with the specific event (e.g. `MouseEvent.t`) - downcast. *)
      Printf.sprintf "WebSharper_UI.TemplateHoleEvent.create %s (fun el ev -> %s el (Obj.magic ev))" name arg
  | Hole.ElemHandler -> Printf.sprintf "WebSharper_UI.TemplateHoleAfterRender.create %s %s" name arg
  | Hole.Var ty -> Printf.sprintf "%s %s %s" (var_fn ty) name arg

let rec impl_of ~server ~base (t : Hole.template) (inner : Hole.template list) : string =
  let tname = match t.name with Some n -> "Some " ^ ocaml_string n | None -> "None" in
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
        | _ -> [ Printf.sprintf "let %s v c = c.%s <- v; c" n n ])
      t.holes
  in
  let holes = String.concat ";\n      " (List.map hole_expr t.holes) in
  let doc =
    if server then
      Printf.sprintf
        "let doc (c : t) : WebSharper_UI.Doc.t =\n  WebSharper_UI.Template.getOrLoad ~base:%s ~name:%s ~src ~refs:references ~keep_unfilled:false\n    [ %s ]"
        (ocaml_string base) tname holes
    else
      Printf.sprintf
        "let doc (c : t) : WebSharper_UI.Doc.t =\n  let fopt = function None -> WebSharper_StdLib.FSharpOption.none () | Some x -> WebSharper_StdLib.FSharpOption.some x in\n  WebSharper_UI.ClientDoc.getOrLoadTemplate %s (fopt %s)\n    (fun () -> WebSharper_UI.DomUtility.parseHTMLIntoFakeRoot src)\n    [ %s ]"
        (ocaml_string base) tname holes
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
       "let references : (string * string * string) list = []";
       create ]
     @ combinators @ [ doc ] @ inner_mods)

let implementation ~server ~base ~src (p : Hole.parsed) : string =
  Printf.sprintf "(* GENERATED from %s.html — do not edit. *)\n\nlet src = %s\n\n%s\n"
    base (ocaml_string src)
    (impl_of ~server ~base p.root p.inner)
