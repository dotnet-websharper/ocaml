(* Split: `secret` is server-only; it must be excluded from the client bundle
   (present only in the server bundle), while the client keeps `f` and the
   `g` rpc proxy. *)
let[@javascript] f x = x + 1
let secret y = y + 777777
let[@rpc] g y = secret y

let () = Console.log (Printf.sprintf "f=%d" (f 41))
