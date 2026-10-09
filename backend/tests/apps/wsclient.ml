(* M1: `ClientServer.client` / `server` markers.

   An external whose result is a function would be uncurried by OCaml, so the
   marker returns an opaque `fn` and a separate `run` applies it. The closure
   passed to `client` is compiled as a standalone client unit. *)
type ('a, 'b) fn

external client : ('a -> 'b) -> ('a, 'b) fn = "wsclient:client" "wsclient:client"
external server : ('a -> 'b) -> ('a, 'b) fn = "wsclient:server" "wsclient:server"
external run : ('a, 'b) fn -> 'a -> 'b = "wsclient:run" "wsclient:run"

let () =
  let f = client (fun x -> x + 1) in
  Console.log (Printf.sprintf "f(41)=%d" (run f 41));

  let g = server (fun x -> x * 2) in
  Console.log (Printf.sprintf "g(21)=%d" (run g 21))
