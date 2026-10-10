open WebSharper_JavaScript

(* Boundary: [@javascript] marks JS-targeted code, [@rpc] a server value the
   client may call through the (asynchronous) proxy; anything else is
   server-only. *)
let[@javascript] f x = x + 1
let[@rpc] g y = y * 2

let () = Console.log (Printf.sprintf "f=%d" (f 41))
