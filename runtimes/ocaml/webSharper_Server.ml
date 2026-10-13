(* Native implementation of the wsocaml server (sitelet) API. Renders
   `Content.Page` from the representation-agnostic `Ssr` node tree and serves it
   through `Wsrpc`. HTML representations (e.g. the WebSharper_UI shadow) live in
   separate packages and convert to `Ssr.node`. *)

type request = {
  method_ : string;
  path : string;
  query : (string * string) list;
  headers : (string * string) list;
  body : string;
}

type response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

type content = response

let parse_query path =
  match String.index_opt path '?' with
  | None -> path, []
  | Some i ->
      let p = String.sub path 0 i in
      let q = String.sub path (i + 1) (String.length path - i - 1) in
      let pairs =
        String.split_on_char '&' q
        |> List.filter_map (fun kv ->
               if kv = "" then None
               else
                 match String.index_opt kv '=' with
                 | Some j -> Some (String.sub kv 0 j, String.sub kv (j + 1) (String.length kv - j - 1))
                 | None -> Some (kv, ""))
      in
      p, pairs

module Content = struct
  let mk ?(status = 200) ?(ct = "text/plain; charset=utf-8") body =
    { status; headers = [ ("Content-Type", ct) ]; body }

  let text s = mk s
  let xml s = mk ~ct:"application/xml; charset=utf-8" s
  let html s = mk ~ct:"text/html; charset=utf-8" s

  let page ?(title = "") ?(head = "") (docs : Ssr.node list list) =
    html
      (Printf.sprintf
         "<!doctype html><html><head><meta charset=\"utf-8\"><title>%s</title>%s</head><body>%s<script ws-replace=\"scripts\"></script></body></html>"
         title head (Ssr.render_nodes (List.concat docs)))

  let status s c = { c with status = s }
  let header k v c = { c with headers = c.headers @ [ (k, v) ] }
end

type ('a) context = { link : 'a -> string; request : request }

module Sitelet = struct
  type ('a) t = {
    route : request -> 'a option;
    link : 'a -> string;
    handle : ('a) context -> 'a -> content;
  }

  let make route link handle = { route; link; handle }
  let empty = { route = (fun _ -> None); link = (fun _ -> "/"); handle = (fun _ _ -> Content.text "") }

  let ( + ) a b =
    {
      route = (fun r -> match a.route r with Some x -> Some x | None -> b.route r);
      link = (fun x -> a.link x);
      handle = (fun ctx x -> a.handle ctx x);
    }

  (* Overwritten by the frontend with a generated router/link. *)
  let infer handle = { route = (fun _ -> None); link = (fun _ -> "/"); handle }

  (* A single content route. *)
  let content method_ path handle =
    {
      route = (fun req -> if req.method_ = method_ && req.path = path then Some () else None);
      link = (fun () -> path);
      handle;
    }
end

let replace_scripts bundle body =
  let pat = "<script ws-replace=\"scripts\"></script>" in
  let tag =
    match bundle with
    | Some b ->
        (* Load the client bundle, then hydrate the SSR regions. Both are module
           scripts (deferred, document order): the bundle registers client code
           before `hydrate()` runs. *)
        Printf.sprintf
          "<script type=\"module\" src=\"/%s.js\"></script>\n<script type=\"module\">globalThis.OCamlRuntime.hydrate();</script>"
          b
    | None -> ""
  in
  let bl = String.length body and pl = String.length pat in
  let buf = Buffer.create bl in
  let rec go i =
    if i + pl <= bl && String.sub body i pl = pat then (Buffer.add_string buf tag; go (i + pl))
    else if i < bl then (Buffer.add_char buf body.[i]; go (i + 1))
  in
  go 0;
  Buffer.contents buf

let content_type_of path =
  match String.lowercase_ascii (Filename.extension path) with
  | ".js" | ".mjs" -> "text/javascript; charset=utf-8"
  | ".json" | ".map" -> "application/json"
  | ".html" | ".htm" -> "text/html; charset=utf-8"
  | ".css" -> "text/css; charset=utf-8"
  | ".svg" -> "image/svg+xml"
  | _ -> "application/octet-stream"

let percent_decode (s : string) : string =
  let n = String.length s in
  let hex c =
    if c >= '0' && c <= '9' then Char.code c - 48
    else if c >= 'a' && c <= 'f' then Char.code c - 87
    else if c >= 'A' && c <= 'F' then Char.code c - 55
    else -1
  in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '%' && !i + 2 < n && hex s.[!i + 1] >= 0 && hex s.[!i + 2] >= 0 then (
      Buffer.add_char b (Char.chr ((hex s.[!i + 1] * 16) + hex s.[!i + 2]));
      i := !i + 3)
    else (Buffer.add_char b s.[!i]; incr i)
  done;
  Buffer.contents b

let serve_file dir path =
  let path = percent_decode path in
  let rel = if String.length path > 0 && path.[0] = '/' then String.sub path 1 (String.length path - 1) else path in
  let full = Filename.concat dir rel in
  if Sys.file_exists full && not (Sys.is_directory full) then (
    let ic = open_in_bin full in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic;
    { status = 200; headers = [ ("Content-Type", content_type_of path) ]; body = s })
  else { status = 404; headers = [ ("Content-Type", "text/plain; charset=utf-8") ]; body = "not found" }

module Server = struct
  let to_wsrpc (c : response) : Wsrpc.response = { status = c.status; headers = c.headers; body = c.body }

  let serve ?(port = 8123) ?static ?bundle (site : ('a) Sitelet.t) =
    let handle (r : Wsrpc.request) =
      let path, query = parse_query r.path in
      let req = { method_ = r.method_; path; query; headers = r.headers; body = r.body } in
      match site.route req with
      | Some ep ->
          let ctx = { link = site.link; request = req } in
          let c = site.handle ctx ep in
          { status = c.status; headers = c.headers; body = replace_scripts bundle c.body }
      | None -> (
          match static with
          | Some dir when r.method_ = "GET" -> serve_file dir path
          | _ ->
              { status = 404; headers = [ ("Content-Type", "text/plain; charset=utf-8") ]; body = "not found" })
    in
    Wsrpc.serve ~port (fun r -> to_wsrpc (handle r))
end
