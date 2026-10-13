(* Template model: hole kinds inferred from an HTML template, mirroring the
   WebSharper.UI templating rules (`ws-*` and legacy `data-*`). *)

type val_ty =
  | String
  | Number
  | Bool
  | DateTime
  | File
  | DomElement
  | StringList
  | Any

type hole_kind =
  | Simple          (* ${Name} in text or attribute value *)
  | Attr            (* ws-attr / data-attr *)
  | Doc             (* ws-hole / ws-replace / data-hole / data-replace *)
  | Event of string (* ws-on<event> / data-event-<event> *)
  | ElemHandler     (* ws-onafterrender *)
  | Var of val_ty   (* ws-var / ws-dom / data-var[-unchecked] *)

type hole = { name : string; mutable kind : hole_kind }

type template = {
  name : string option; (* None = the file's root template *)
  holes : hole list;
  anchors : string list;
  body : Markup.node list; (* the nodes the template renders *)
}

type parsed = { root : template; inner : template list }

let starts_with (pre : string) (s : string) =
  String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

(* Names of `${Name}` holes in a string. *)
let split_holes (s : string) : string list =
  let n = String.length s in
  let acc = ref [] in
  let i = ref 0 in
  while !i < n - 1 do
    if s.[!i] = '$' && s.[!i + 1] = '{' then begin
      let j = ref (!i + 2) in
      while !j < n && s.[!j] <> '}' do incr j done;
      if !j < n then begin
        acc := String.sub s (!i + 2) (!j - !i - 2) :: !acc;
        i := !j + 1
      end
      else i := n
    end
    else incr i
  done;
  List.rev !acc

type acc = { mutable holes : hole list; mutable anchors : string list }

let new_acc () = { holes = []; anchors = [] }

let merge_kind (k1 : hole_kind) (k2 : hole_kind) : hole_kind =
  match k1, k2 with
  | a, b when a = b -> a
  | Simple, k -> k
  | k, Simple -> k
  | Var _, Var _ -> k1
  | a, _ -> a

let add_hole acc name kind =
  let name = String.trim name in
  if name <> "" then
    match List.find_opt (fun (h : hole) -> h.name = name) acc.holes with
    | Some h -> h.kind <- merge_kind h.kind kind
    | None -> acc.holes <- acc.holes @ [ { name; kind } ]

let var_type_of (el : Markup.element) : val_ty =
  match String.lowercase_ascii el.tag with
  | "textarea" -> String
  | "select" -> (match Markup.find_attr el "multiple" with Some _ -> StringList | None -> Any)
  | "input" -> (
      match Markup.find_attr el "type" with
      | Some t -> (
          match String.lowercase_ascii t with
          | "number" | "range" -> Number
          | "checkbox" -> Bool
          | "datetime-local" -> DateTime
          | "file" -> File
          | _ -> Any)
      | None -> Any)
  | _ -> Any

(* Collect the holes of an attribute, handling `ws-*` / `data-*` and `${}`. *)
let scan_attr acc el (k, v) =
  List.iter (fun n -> add_hole acc n Simple) (split_holes v);
  let kl = String.lowercase_ascii k in
  if kl = "ws-attr" || kl = "data-attr" then add_hole acc v Attr
  else if kl = "ws-hole" || kl = "ws-replace" || kl = "data-hole" || kl = "data-replace" then
    add_hole acc v Doc
  else if kl = "ws-var" || kl = "data-var" || kl = "data-var-unchecked" then
    add_hole acc v (Var (var_type_of el))
  else if kl = "ws-dom" then add_hole acc v (Var DomElement)
  else if kl = "ws-onafterrender" then add_hole acc v ElemHandler
  else if kl = "ws-anchor" then acc.anchors <- acc.anchors @ [ v ]
  else if starts_with "ws-on" kl then
    add_hole acc v (Event (String.sub kl 5 (String.length kl - 5)))
  else if starts_with "data-event-" kl then
    add_hole acc v (Event (String.sub kl 11 (String.length kl - 11)))

let analyze (nodes : Markup.node list) : parsed =
  let inner : template list ref = ref [] in
  let rec register_inner name (body : Markup.node list) =
    let sub = new_acc () in
    scan_nodes sub body;
    inner :=
      { name = Some name; holes = sub.holes; anchors = sub.anchors; body } :: !inner
  and scan_nodes acc nodes = List.iter (scan_node acc) nodes
  and scan_node acc (node : Markup.node) =
    match node with
    | Markup.Text s -> List.iter (fun n -> add_hole acc n Simple) (split_holes s)
    | Markup.Comment _ | Markup.Doctype _ -> ()
    | Markup.Element el -> scan_element acc el
  and scan_element acc (el : Markup.element) =
    match Markup.find_attr el "ws-template" with
    | Some name -> register_inner name [ Markup.Element el ]
    | None -> (
        match Markup.find_attr el "ws-children-template" with
        | Some name -> register_inner name el.children
        | None -> (
            let is_template_elem = String.lowercase_ascii el.tag = "template" in
            if is_template_elem then
              match
                ( Markup.find_attr el "name",
                  Markup.find_attr el "id" )
              with
              | Some nm, _ | None, Some nm -> register_inner nm el.children
              | None, None -> ()
            else begin
              List.iter (scan_attr acc el) el.attrs;
              scan_nodes acc el.children
            end))
  in
  let root_acc = new_acc () in
  scan_nodes root_acc nodes;
  { root = { name = None; holes = root_acc.holes; anchors = root_acc.anchors; body = nodes };
    inner = List.rev !inner }
