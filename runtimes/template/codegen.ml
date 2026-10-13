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
  | Hole.File -> "WebSharper_UI.Template.file array"
  | Hole.String | Hole.StringList | Hole.DateTime | Hole.DomElement | Hole.Any -> "string"

let event_type name =
  match String.lowercase_ascii name with
  | "click" | "dblclick" | "contextmenu" | "mousedown" | "mouseup" | "mousemove"
  | "mouseover" | "mouseout" | "mouseenter" | "mouseleave" ->
      "WebSharper_UI.Template.mouse_event"
  | "keydown" | "keyup" | "keypress" -> "WebSharper_UI.Template.keyboard_event"
  | "focus" | "blur" | "focusin" | "focusout" -> "WebSharper_UI.Template.focus_event"
  | _ -> "WebSharper_UI.Template.event"

let element_type = "WebSharper_UI.Template.element"

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
  | Hole.Bool -> "varBool"
  | Hole.Number -> "varFloat"
  | Hole.File -> "varFile"
  | _ -> "varStr"

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

let anchors_type (t : Hole.template) =
  if t.anchors = [] then "unit"
  else
    "{ "
    ^ String.concat "; "
        (List.map (fun a -> Printf.sprintf "%s : %s" (lcfirst a) element_type) t.anchors)
    ^ " }"

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
  let fn =
    match h.kind with
    | Hole.Simple -> "text"
    | Hole.Doc -> "elt"
    | Hole.Attr -> "attr"
    | Hole.Event _ -> "event"
    | Hole.ElemHandler -> "afterRender"
    | Hole.Var ty -> var_fn ty
  in
  let arg = if is_var h then "c.vars." ^ lcfirst h.name else "c." ^ lcfirst h.name in
  Printf.sprintf "WebSharper_UI.Template.%s %s %s" fn (ocaml_string h.name) arg

let rec impl_of ~base (t : Hole.template) (inner : Hole.template list) : string =
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
                "let %s_withModel v c = c.%s <- (fun target event -> v { vars = c.vars; anchors = %s; target; event }); c"
                n n (anchors_expr t) ]
        | Hole.ElemHandler -> [ Printf.sprintf "let %s v c = c.%s <- v; c" n n ]
        | Hole.Var _ -> []
        | _ -> [ Printf.sprintf "let %s v c = c.%s <- v; c" n n ])
      t.holes
  in
  let holes = String.concat ";\n      " (List.map hole_expr t.holes) in
  let doc =
    Printf.sprintf
      "let doc (c : t) : WebSharper_UI.Doc.t =\n  WebSharper_UI.Template.getOrLoad ~base:%s ~name:%s ~src ~refs:references ~keep_unfilled:false\n    [ %s ]"
      (ocaml_string base) tname holes
  in
  let inner_mods =
    List.map
      (fun (sub : Hole.template) ->
        Printf.sprintf "module %s = struct\n%s\nend" (String.capitalize_ascii (Option.get sub.name))
          (impl_of ~base sub []))
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

let implementation ~base ~src (p : Hole.parsed) : string =
  Printf.sprintf "(* GENERATED from %s.html — do not edit. *)\n\nlet src = %s\n\n%s\n"
    base (ocaml_string src)
    (impl_of ~base p.root p.inner)
