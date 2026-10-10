(* Minimal native OCaml HTTP server for wsocaml.

   Low-level: `serve ?port handle` reads requests and writes responses. The
   program supplies `handle` for non-RPC requests. `POST /rpc` is dispatched to
   the registered JSON-RPC handlers. *)

type request = {
  method_ : string;
  path : string;
  headers : (string * string) list;
  body : string;
}

type response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

let handlers : (string, Yojson.Safe.t list -> Yojson.Safe.t) Hashtbl.t = Hashtbl.create 16
let register name fn = Hashtbl.replace handlers name fn

let rpc_response body =
  try
    let req = Yojson.Safe.from_string body in
    let name = Yojson.Safe.Util.(member "name" req |> to_string) in
    let args = Yojson.Safe.Util.(member "args" req |> to_list) in
    let result = (Hashtbl.find handlers name) args in
    Yojson.Safe.to_string (`Assoc [ ("result", result) ])
  with e -> Yojson.Safe.to_string (`Assoc [ ("error", `String (Printexc.to_string e)) ])

let read_all ic n =
  let b = Bytes.create n in
  really_input ic b 0 n;
  Bytes.to_string b

let handle_client (handle : request -> response) fd =
  let ic = Unix.in_channel_of_descr fd in
  let oc = Unix.out_channel_of_descr fd in
  let req_line = try input_line ic with End_of_file -> "" in
  let parts = String.split_on_char ' ' req_line in
  let method_ = match parts with m :: _ -> m | [] -> "" in
  let path = match parts with _ :: p :: _ -> p | _ -> "" in
  let content_length = ref 0 in
  let headers = ref [] in
  let rec header_lines () =
    match input_line ic with
    | line ->
        if String.trim line <> "" then (
          (match String.index_opt line ':' with
           | Some i ->
               let k = String.trim (String.sub line 0 i) in
               let v = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
               headers := (k, v) :: !headers;
               if String.lowercase_ascii k = "content-length" then content_length := int_of_string v
           | None -> ());
          header_lines ())
    | exception End_of_file -> ()
  in
  header_lines ();
  let body = if !content_length > 0 then read_all ic !content_length else "" in
  let req = { method_ = method_; path; headers = List.rev !headers; body } in
  let resp =
    if String.length path >= 4 && String.sub path 0 4 = "/rpc" then
      {
        status = 200;
        headers = [ ("Content-Type", "application/json"); ("Access-Control-Allow-Origin", "*") ];
        body = rpc_response body;
      }
    else handle req
  in
  Printf.fprintf oc "HTTP/1.1 %d \r\n" resp.status;
  List.iter (fun (k, v) -> Printf.fprintf oc "%s: %s\r\n" k v) resp.headers;
  Printf.fprintf oc "Content-Length: %d\r\nConnection: close\r\n\r\n%s" (String.length resp.body) resp.body;
  flush oc;
  Unix.close fd

let serve ?(port = 8123) (handle : request -> response) =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.listen sock 8;
  Printf.printf "wsocaml server on http://127.0.0.1:%d/\n%!" port;
  while true do
    let fd, _ = Unix.accept sock in
    try handle_client handle fd with _ -> (try Unix.close fd with _ -> ())
  done
