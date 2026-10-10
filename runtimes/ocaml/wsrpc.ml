(* Minimal native OCaml JSON-RPC server for wsocaml client/server.

   Endpoint: POST /rpc with body {"name": <string>, "args": [<json>...]} and
   response {"result": <json>} (or {"error": <string>}). Handlers are registered
   by the server program. *)

let read_all ic n =
  let b = Bytes.create n in
  really_input ic b 0 n;
  Bytes.to_string b

let handle_client (handlers : (string, Yojson.Safe.t list -> Yojson.Safe.t) Hashtbl.t) fd =
  let ic = Unix.in_channel_of_descr fd in
  let oc = Unix.out_channel_of_descr fd in
  ignore (input_line ic);
  let content_length = ref 0 in
  let rec loop () =
    let l = input_line ic in
    if String.trim l <> "" then begin
      (match String.index_opt l ':' with
      | Some i ->
          let k = String.lowercase_ascii (String.trim (String.sub l 0 i)) in
          if k = "content-length" then
            content_length :=
              int_of_string (String.trim (String.sub l (i + 1) (String.length l - i - 1)))
      | None -> ());
      loop ()
    end
  in
  loop ();
  let body = if !content_length > 0 then read_all ic !content_length else "" in
  let response_body =
    try
      let req = Yojson.Safe.from_string body in
      let name = Yojson.Safe.Util.(member "name" req |> to_string) in
      let args = Yojson.Safe.Util.(member "args" req |> to_list) in
      let result = (Hashtbl.find handlers name) args in
      Yojson.Safe.to_string (`Assoc [ ("result", result) ])
    with e -> Yojson.Safe.to_string (`Assoc [ ("error", `String (Printexc.to_string e)) ])
  in
  Printf.fprintf oc
    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n%s"
    (String.length response_body) response_body;
  flush oc;
  Unix.close fd

let serve ?(port = 8123) handlers =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.listen sock 8;
  Printf.printf "wsocaml rpc server on http://127.0.0.1:%d/rpc\n%!" port;
  while true do
    let fd, _ = Unix.accept sock in
    try handle_client handlers fd with _ -> (try Unix.close fd with _ -> ())
  done
