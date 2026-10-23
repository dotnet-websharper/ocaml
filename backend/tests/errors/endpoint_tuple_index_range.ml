(* On a tuple payload the slot names are the argument indexes, so an index
   outside the arity names no argument. *)
type endpoint =
  | Home [@endpoint "GET /"]
  | Move of int [@endpoint "GET /move/@1"]
