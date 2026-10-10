(* B2: RPC. `f` is JS-targeted (client); `g` is a server value the client
   reaches through an asynchronous `rpcCall` proxy. The OCaml proxy returns a
   promise, so the program does not call `g` directly here; the driver awaits
   the runtime call. *)
let[@javascript] f x = x + 1
let[@rpc] g y = y * 2

let () = Console.log (Printf.sprintf "f=%d" (f 41))
