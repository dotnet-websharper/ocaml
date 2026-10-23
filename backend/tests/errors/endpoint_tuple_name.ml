(* A tuple payload is positional: its slots are `@0`, `@1`, … (not free names). *)
type endpoint =
  | Home [@endpoint "GET /"]
  | Move of int * string [@endpoint "PUT /move/@from/@to"]
