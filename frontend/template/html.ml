(* A small, lenient HTML parser for wsocaml templates.

   Template HTML is usually well-formed, so we do not implement full HTML5
   tree-construction / error recovery; we scan tags literally (like WS's
   templating parser, which disables tag fixing and auto-closing). DOCTYPE and
   comments are preserved as first-class nodes because templates must be able to
   emit them. *)

type node =
  | Text of string
  | Comment of string
  | Doctype of string
  | Element of element

and element = {
  tag : string;
  attrs : (string * string) list;
  mutable children : node list;
  self_closing : bool;
}

(* Elements whose content is raw text (not markup). *)
let raw_text_tags = [ "script"; "style"; "textarea"; "title" ]

(* Void elements: never have children and close immediately. *)
let void_tags =
  [ "area"; "base"; "br"; "col"; "embed"; "hr"; "img"; "input"; "link"; "meta";
    "param"; "source"; "track"; "wbr" ]

let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r'

let is_name_char c =
  not (is_ws c) && c <> '>' && c <> '/' && c <> '<' && c <> '='

let parse (src : string) : node list =
  let n = String.length src in
  let pos = ref 0 in
  let root = { tag = ""; attrs = []; children = []; self_closing = false } in
  let stack = ref [ root ] in
  let add_node nd =
    match !stack with
    | top :: _ -> top.children <- top.children @ [ nd ]
    | [] -> ()
  in
  let starts_with s =
    let l = String.length s in
    !pos + l <= n && String.sub src !pos l = s
  in
  let skip_ws () = while !pos < n && is_ws src.[!pos] do incr pos done in
  let read_name () =
    let start = !pos in
    while !pos < n && is_name_char src.[!pos] do incr pos done;
    String.sub src start (!pos - start)
  in
  let skip_to_gt () =
    while !pos < n && src.[!pos] <> '>' do incr pos done;
    if !pos < n then incr pos
  in
  while !pos < n do
    if starts_with "<!--" then begin
      pos := !pos + 4;
      let start = !pos in
      while !pos < n && not (starts_with "-->") do incr pos done;
      let content = String.sub src start (!pos - start) in
      if !pos < n then pos := !pos + 3;
      add_node (Comment content)
    end
    else if starts_with "<!" then begin
      let start = !pos in
      skip_to_gt ();
      add_node (Doctype (String.sub src start (!pos - start)))
    end
    else if starts_with "</" then begin
      pos := !pos + 2;
      skip_ws ();
      ignore (read_name ());
      skip_to_gt ();
      (match !stack with _ :: (_ :: _ as rest) -> stack := rest | _ -> ())
    end
    else if starts_with "<" && !pos + 1 < n && not (is_ws src.[!pos + 1]) then begin
      incr pos;
      let tag = read_name () in
      let attrs = ref [] in
      let self_closing = ref false in
      let continue = ref true in
      while !continue && !pos < n do
        skip_ws ();
        if !pos < n && src.[!pos] = '>' then (incr pos; continue := false)
        else if !pos < n && src.[!pos] = '/' then (incr pos; self_closing := true)
        else begin
          let aname = read_name () in
          if aname = "" then incr pos
          else begin
            skip_ws ();
            if !pos < n && src.[!pos] = '=' then begin
              incr pos;
              skip_ws ();
              let aval =
                if !pos < n && (src.[!pos] = '"' || src.[!pos] = '\'') then begin
                  let q = src.[!pos] in
                  incr pos;
                  let s = !pos in
                  while !pos < n && src.[!pos] <> q do incr pos done;
                  let v = String.sub src s (!pos - s) in
                  if !pos < n then incr pos;
                  v
                end
                else begin
                  let s = !pos in
                  while !pos < n && not (is_ws src.[!pos]) && src.[!pos] <> '>' do incr pos done;
                  String.sub src s (!pos - s)
                end
              in
              attrs := (aname, aval) :: !attrs
            end
            else attrs := (aname, "") :: !attrs
          end
        end
      done;
      let tag_l = String.lowercase_ascii tag in
      let el =
        { tag; attrs = List.rev !attrs; children = []; self_closing = !self_closing }
      in
      add_node (Element el);
      if (not !self_closing) && not (List.mem tag_l void_tags) then begin
        if List.mem tag_l raw_text_tags then begin
          let close = "</" ^ tag_l in
          let s = !pos in
          let found = ref (-1) in
          let j = ref !pos in
          let clen = String.length close in
          while !found < 0 && !j <= n - clen do
            if String.lowercase_ascii (String.sub src !j clen) = close then found := !j
            else incr j
          done;
          let content =
            if !found >= 0 then String.sub src s (!found - s) else String.sub src s (n - s)
          in
          el.children <- [ Text content ];
          if !found >= 0 then (pos := !found + clen; skip_to_gt ()) else pos := n
        end
        else stack := el :: !stack
      end
    end
    else begin
      (* text run (consume a stray '<' as literal text to guarantee progress) *)
      if src.[!pos] = '<' then (add_node (Text "<"); incr pos)
      else begin
        let s = !pos in
        while !pos < n && src.[!pos] <> '<' do incr pos done;
        let t = String.sub src s (!pos - s) in
        if t <> "" then add_node (Text t)
      end
    end
  done;
  root.children

(* Depth-first fold over all element nodes. *)
let rec iter_elements (f : element -> unit) (nodes : node list) : unit =
  List.iter
    (fun nd ->
      match nd with
      | Element el ->
          f el;
          iter_elements f el.children
      | _ -> ())
    nodes

let find_attr (el : element) (name : string) : string option =
  let name = String.lowercase_ascii name in
  List.find_map
    (fun (k, v) -> if String.lowercase_ascii k = name then Some v else None)
    el.attrs

let has_attr (el : element) (name : string) : bool = find_attr el name <> None
