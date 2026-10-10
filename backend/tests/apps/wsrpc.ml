(* B2: RPC. `f` is JS-targeted (client); `g` is a server value the client
   reaches through an asynchronous `rpcCall` proxy. `[@rpc]` handlers return
   `'a Async.t`, so client code can sequence calls with `Async.bind`/`Async.map`
   and observe them with `Async.run`. *)
let[@javascript] f x = x + 1
let[@rpc] g y = Async.return (y * 2)
let[@javascript] bump y = Async.bind (g y) (fun v -> Async.return (v + 1))

let () = Console.log (Printf.sprintf "f=%d" (f 41))
