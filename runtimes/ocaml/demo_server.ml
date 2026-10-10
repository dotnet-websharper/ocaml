let () =
  let handlers = Hashtbl.create 8 in
  Hashtbl.add handlers "g" (function [ `Int y ] -> `Int (y * 2) | _ -> `Null);
  Wsrpc.serve ~port:8123 handlers
