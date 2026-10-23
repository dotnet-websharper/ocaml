(* Every constructor of the endpoint variant must carry [@endpoint ...]. *)
type endpoint =
  | Home [@endpoint "GET /"]
  | Echo of string
