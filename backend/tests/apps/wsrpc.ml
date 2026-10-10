(* B2: RPC. `f` is JS-targeted (client); `g` is a server value the client calls
   through an `rpcCall` proxy, served by the emitted server bundle. *)
let[@javascript] f x = x + 1
let[@rpc] g y = y * 2

let () =
  Console.log (Printf.sprintf "f=%d" (f 41));
  Console.log (Printf.sprintf "g=%d" (g 21))
