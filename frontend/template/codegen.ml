(* Emit an OCaml module (signature + implementation) for a parsed template file.

   Generated surface: a class type of `unit` setters, var getters (unprefixed),
   `_withModel` event setters, a `doc` terminal, and module-level pipe
   combinators; inner templates become submodules. The implementation is
   structure-as-data: it passes the raw template source and holes to
   `WebSharper_UI.Template.getOrLoad`, so one generated module serves both tiers.

   Anchors and cross-file `references` are placeholders for now. *)

let lcfirst s = if s = "" then s else String.uncapitalize_ascii s

let val_ty_to_string = function
  | Hole.String -> "string"
  | Hole.Number -> "float"
  | Hole.Bool -> "bool"
  | Hole.StringList | Hole.DateTime | Hole.File | Hole.DomElement | Hole.Any -> "string"

(* M-T1 uses the base `Event.t` for all event holes (matches the client
   `TemplateHoleEvent.create`); per-event precision (MouseEvent/KeyboardEvent)
   is a later refinement. *)
let event_type (_ : string) = "WebSharper_UI.Template.event"

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
let is_event (h : Hole.hole) = match h.Hole.kind with Hole.Event _ -> true | _ -> false

let def_var = function
  | Hole.Number -> "0."
  | Hole.Bool -> "false"
  | Hole.String | Hole.Any | Hole.StringList | Hole.DateTime | Hole.File | Hole.DomElement -> "\"\""

(* --- signature -------------------------------------------------------------- *)

let member_sigs (h : Hole.hole) : string list =
  let n = lcfirst h.name in
  match h.kind with
  | Hole.Simple -> [ Printf.sprintf "method %s : string -> unit" n ]
  | Hole.Doc -> [ Printf.sprintf "method %s : WebSharper_UI.Doc.t -> unit" n ]
  | Hole.Attr -> [ Printf.sprintf "method %s : WebSharper_UI.Attr.t -> unit" n ]
  | Hole.Event ev ->
      [ Printf.sprintf "method %s : (WebSharper_UI.Template.element -> %s -> unit) -> unit" n (event_type ev);
        Printf.sprintf "method %s_withModel : (%s event -> unit) -> unit" n (event_type ev) ]
  | Hole.ElemHandler -> [ Printf.sprintf "method %s : (WebSharper_UI.Template.element -> unit) -> unit" n ]
  | Hole.Var ty -> [ Printf.sprintf "method %s : %s WebSharper_UI.Var.t" n (val_ty_to_string ty) ]

let comb_sigs (h : Hole.hole) : string list =
  let n = lcfirst h.name in
  match h.kind with
  | Hole.Simple -> [ Printf.sprintf "val %s : string -> t -> t" n ]
  | Hole.Doc -> [ Printf.sprintf "val %s : WebSharper_UI.Doc.t -> t -> t" n ]
  | Hole.Attr -> [ Printf.sprintf "val %s : WebSharper_UI.Attr.t -> t -> t" n ]
  | Hole.Event ev ->
      [ Printf.sprintf "val %s : (WebSharper_UI.Template.element -> %s -> unit) -> t -> t" n (event_type ev);
        Printf.sprintf "val %s_withModel : (%s event -> unit) -> t -> t" n (event_type ev) ]
  | Hole.ElemHandler -> [ Printf.sprintf "val %s : (WebSharper_UI.Template.element -> unit) -> t -> t" n ]
  | Hole.Var _ -> [] (* vars are getters; inject via create *)

let vars_type (t : Hole.template) =
  let vs = vars_of t in
  if vs = [] then "unit"
  else
    "{ "
    ^ String.concat "; "
        (List.map
           (fun (h : Hole.hole) ->
             match h.Hole.kind with
             | Hole.Var ty -> Printf.sprintf "%s : %s WebSharper_UI.Var.t" (lcfirst h.name) (val_ty_to_string ty)
             | _ -> "")
           vs)
    ^ " }"

let vars_record (t : Hole.template) =
  let vs = vars_of t in
  if vs = [] then "()"
  else
    "({ "
    ^ String.concat "; " (List.map (fun (h : Hole.hole) -> Printf.sprintf "%s = %s" (lcfirst h.Hole.name) (lcfirst h.Hole.name)) vs)
    ^ " } : vars)"

let event_type_decl (_ : Hole.template) =
  "type 'e event = { vars : vars; anchors : anchors; target : WebSharper_UI.Template.element; event : 'e }"

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
      "type anchors = unit";
      event_type_decl t;
      "class type t = object";
      "  " ^ String.concat "\n  " (List.concat_map member_sigs t.holes @ [ "method vars : vars"; "method doc : ?keep_unfilled:bool -> unit -> WebSharper_UI.Doc.t" ]);
      "end";
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

let var_fn = function
  | Hole.String | Hole.Any -> "varStr"
  | Hole.Bool -> "varBool"
  | Hole.Number -> "varFloat"
  | Hole.StringList | Hole.DateTime | Hole.File | Hole.DomElement -> "varStr"

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
  Printf.sprintf "WebSharper_UI.Template.%s %s %s" fn (ocaml_string h.name) (lcfirst h.name)

let rec impl_of ~base (t : Hole.template) (inner : Hole.template list) : string =
  let tname = match t.name with Some n -> "Some " ^ ocaml_string n | None -> "None" in
  let fields =
    List.map
      (fun (h : Hole.hole) ->
        let n = lcfirst h.name in
        match h.kind with
        | Hole.Simple -> Printf.sprintf "val mutable %s : string = \"\"" n
        | Hole.Doc -> Printf.sprintf "val mutable %s : WebSharper_UI.Doc.t = WebSharper_UI.Doc.empty ()" n
        | Hole.Attr -> Printf.sprintf "val mutable %s : WebSharper_UI.Attr.t = WebSharper_UI.Attr.empty ()" n
        | Hole.Var ty -> Printf.sprintf "val %s : %s WebSharper_UI.Var.t = WebSharper_UI.Var.create (%s)" n (val_ty_to_string ty) (def_var ty)
        | Hole.Event ev -> Printf.sprintf "val mutable %s : WebSharper_UI.Template.element -> %s -> unit = (fun _ _ -> ())" n (event_type ev)
        | Hole.ElemHandler -> Printf.sprintf "val mutable %s : WebSharper_UI.Template.element -> unit = (fun _ -> ())" n)
      t.holes
  in
  let members =
    List.concat_map
      (fun (h : Hole.hole) ->
        let n = lcfirst h.name in
        match h.kind with
        | Hole.Simple | Hole.Doc | Hole.Attr -> [ Printf.sprintf "method %s v = %s <- v" n n ]
        | Hole.Var _ -> [ Printf.sprintf "method %s = %s" n n ]
        | Hole.Event _ ->
            [ Printf.sprintf "method %s f = %s <- f" n n;
              Printf.sprintf
                "method %s_withModel f = %s <- (fun target event -> f { vars = self#vars; anchors = (); target; event })"
                n n ]
        | Hole.ElemHandler -> [ Printf.sprintf "method %s f = %s <- f" n n ])
      t.holes
  in
  let doc_method =
    let holes = String.concat ";\n      " (List.map hole_expr t.holes) in
    Printf.sprintf
      "method doc ?(keep_unfilled = false) () =\n      WebSharper_UI.Template.getOrLoad ~base:%s ~name:%s ~src ~refs:references ~keep_unfilled\n        [ %s ]"
      (ocaml_string base) tname holes
  in
  let class_def =
    Printf.sprintf "class t = object (self)\n    %s\n    method vars = %s\n    %s\n    %s\n  end"
      (String.concat "\n    " fields)
      (vars_record t)
      (String.concat "\n    " members)
      doc_method
  in
  let combinators =
    List.concat_map
      (fun (h : Hole.hole) ->
        let n = lcfirst h.name in
        match h.kind with
        | Hole.Event _ ->
            [ Printf.sprintf "let %s v (c : t) = c#%s v; c" n n;
              Printf.sprintf "let %s_withModel v (c : t) = c#%s_withModel v; c" n n ]
        | Hole.ElemHandler -> [ Printf.sprintf "let %s v (c : t) = c#%s v; c" n n ]
        | Hole.Var _ -> []
        | _ -> [ Printf.sprintf "let %s v (c : t) = c#%s v; c" n n ])
      t.holes
    @ [ "let doc (c : t) = c#doc ()" ]
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
       "type anchors = unit";
       event_type_decl t;
       "let references : (string * string * string) list = []";
       class_def;
       "let create () : t = new t" ]
     @ combinators @ inner_mods)

let implementation ~base ~src (p : Hole.parsed) : string =
  Printf.sprintf "(* GENERATED from %s.html — do not edit. *)\n\nlet src = %s\n\n%s\n"
    base (ocaml_string src)
    (impl_of ~base p.root p.inner)
