(* An endpoint `@name` must name a payload slot. *)
type endpoint =
  | Home [@endpoint "GET /"]
  | User of { id : int; name : string } [@endpoint "GET /user/@idd/@name"]
