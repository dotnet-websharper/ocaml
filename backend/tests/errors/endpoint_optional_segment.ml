(* Optional segments are not supported: a trailing '?' only starts an (empty)
   query part, so it is rejected rather than silently treated as `@page`. *)
type endpoint =
  | Home [@endpoint "GET /"]
  | Posts of { tag : string; page : int } [@endpoint "GET /posts/@tag/@page?"]
