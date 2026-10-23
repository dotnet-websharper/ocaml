(* Every payload slot must be bound. *)
type endpoint =
  | Home [@endpoint "GET /"]
  | User of { id : int; name : string } [@endpoint "GET /user/@id"]
