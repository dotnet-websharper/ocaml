(* Minimal native OCaml HTTP server for wsocaml client/server apps.

   Endpoints:
   - `POST /rpc` with body {"name": <string>, "args": [<json>…]} -> {"result": <json>}
     (handlers are registered by the server program).
   - `GET /` (or any other path) -> the rendered page, when a `?page` is given. *)

let read_all ic n =
  let b = Bytes.create n in
  really_input ic b 0 n;
  Bytes.to_string b

let rpc_response (handlers : (string, Yojson.Safe.t list -> Yojson.Safe.t) Hashtbl.t) body =
  try
    let req = Yojson.Safe.from_string body in
    let name = Yojson.Safe.Util.(member "name" req |> to_string) in
    let args = Yojson.Safe.Util.(member "args" req |> to_list) in
    let result = (Hashtbl.find handlers name) args in
    Yojson.Safe.to_string (`Assoc [ ("result", result) ])
  with e -> Yojson.Safe.to_string (`Assoc [ ("error", `String (Printexc.to_string e)) ])

let handle_client ?page handlers fd =
  let ic = Unix.in_channel_of_descr fd in
  let oc = Unix.out_channel_of_descr fd in
  let req_line = try input_line ic with End_of_file -> "" in
  let parts = String.split_on_char ' ' req_line in
  let method_ = match parts with m :: _ -> m | [] -> "" in
  let path = match parts with _ :: p :: _ -> p | _ -> "" in
  let content_length = ref 0 in
  let rec headers () =
    match input_line ic with
    | line ->
        if String.trim line <> "" then (
          (match String.index_opt line ':' with
           | Some i ->
               let k = String.lowercase_ascii (String.trim (String.sub line 0 i)) in
               if k = "content-length" then
                 content_length :=
                   int_of_string (String.trim (String.sub line (i + 1) (String.length line - i - 1)))
           | None -> ());
          headers ())
    | exception End_of_file -> ()
  in
  headers ();
  let body = if !content_length > 0 then read_all ic !content_length else "" in
  let is_rpc = String.length path >= 4 && String.sub path 0 4 = "/rpc" in
  let response_body, content_type =
    if is_rpc then (rpc_response handlers body, "application/json")
    else
      match page with
      | Some f when method_ = "GET" -> (f (), "text/html; charset=utf-8")
      | _ -> ("not found", "text/plain")
  in
  Printf.fprintf oc
    "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n%s"
    content_type (String.length response_body) response_body;
  flush oc;
  Unix.close fd

let serve ?(port = 8123) ?page handlers =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.listen sock 8;
  Printf.printf "wsocaml server on http://127.0.0.1:%d/\n%!" port;
  while true do
    let fd, _ = Unix.accept sock in
    try handle_client ?page handlers fd with _ -> (try Unix.close fd with _ -> ())
  done
