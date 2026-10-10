(* Minimal native HTML builder + renderer for server-side rendering.

   Server-only OCaml code builds a page tree and renders it to an HTML string;
   `[@client]` regions are emitted as `<div id="…" data-ws-key="…">` placeholders
   the client runtime hydrates (see docs/client-server.md §4). *)

type node =
  | Text of string
  | Raw of string
  | El of string * (string * string) list * node list

let text s = Text s
let raw s = Raw s
let el name attrs children = El (name, attrs, children)

let escape (s : string) =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let rec render_node = function
  | Text s -> escape s
  | Raw s -> s
  | El (name, attrs, children) ->
      let a =
        String.concat "" (List.map (fun (k, v) -> Printf.sprintf " %s=\"%s\"" k (escape v)) attrs)
      in
      Printf.sprintf "<%s%s>%s</%s>" name a
        (String.concat "" (List.map render_node children))
        name

let render ?(title = "") ?(scripts = []) (body : node list) =
  let head = Printf.sprintf "<meta charset=\"utf-8\"><title>%s</title>" (escape title) in
  let sc =
    String.concat ""
      (List.map (fun src -> Printf.sprintf "<script type=\"module\" src=\"%s\"></script>" src) scripts)
  in
  "<!doctype html><html><head>" ^ head ^ "</head><body>"
  ^ String.concat "" (List.map render_node body)
  ^ sc ^ "</body></html>"

(* A `[@client]` hydration region: `<div id="…" data-ws-key="…">content</div>`.
   The content is the server-rendered initial markup. *)
let client_region ?id key (content : node list) =
  let id = match id with Some i -> i | None -> key in
  El ("div", [ "id", id; "data-ws-key", key ], content)

(* Rendered `[@client]` regions, populated by `Doc.runById` on the server. *)
let regions : (string, string) Hashtbl.t = Hashtbl.create 16
let order : string list ref = ref []

let regions_reset () =
  Hashtbl.reset regions;
  order := []

let regions_replace id html =
  if not (Hashtbl.mem regions id) then order := id :: !order;
  Hashtbl.replace regions id html

(* A full page assembled from the rendered regions (in insertion order). *)
let page ?(title = "") ?(scripts = []) () =
  let body =
    List.rev_map (fun id -> client_region ~id id [ raw (Hashtbl.find regions id) ]) !order
  in
  render ~title ~scripts body
