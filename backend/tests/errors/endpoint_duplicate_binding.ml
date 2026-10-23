(* The `@names` must be a bijection over the payload slots. *)
type endpoint =
  | Home [@endpoint "GET /"]
  | User of { id : int; name : string } [@endpoint "GET /user/@id/@id"]
