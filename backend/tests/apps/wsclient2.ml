(* M2: capture. The `client` closure `fun x -> x + base` captures `base`; it is
   emitted as a factory `(env) => closure`, reading `base` from `env`. *)
type ('a, 'b) fn

external client : ('a -> 'b) -> ('a, 'b) fn = "wsclient:client" "wsclient:client"
external run : ('a, 'b) fn -> 'a -> 'b = "wsclient:run" "wsclient:run"

let () =
  let base = 10 in
  let f = client (fun x -> x + base) in
  Console.log (Printf.sprintf "f(41)=%d" (run f 41));
  Console.log (Printf.sprintf "base=%d" base)
