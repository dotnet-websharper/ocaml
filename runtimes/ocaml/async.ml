(* Native Async for the generated RPC server (the client uses the generated
   WebSharper_JavaScript.Async, which is promise-backed). Computations are CPS
   and run synchronously in the server's request handler. *)
type 'a t = ('a -> unit) -> unit

let return v k = k v
let bind a f k = a (fun v -> f v k)
let map f a k = a (fun v -> k (f v))
let run k a = a k

let run_sync a =
  let r = ref None in
  a (fun v -> r := Some v);
  match !r with
  | Some v -> v
  | None -> failwith "Async.run_sync: computation did not complete synchronously"
