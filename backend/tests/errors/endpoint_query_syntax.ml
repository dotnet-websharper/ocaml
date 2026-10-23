(* A query item must be `key=@name`; nothing in the route is silently ignored. *)
type endpoint =
  | Home [@endpoint "GET /"]
  | Search of { q : string } [@endpoint "GET /search?flag"]
