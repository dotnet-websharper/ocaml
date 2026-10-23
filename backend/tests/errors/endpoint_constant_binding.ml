(* A constant constructor has no payload slots, so it cannot bind anything. *)
type endpoint =
  | Home [@endpoint "GET /"]
  | Plain [@endpoint "GET /plain/@x"]
