
type shape =
  | Circle of float
  | Rectangle of float * float

let area x =
  match x with
  | Circle r ->
      3.141592653589793 *. r *. r
  | Rectangle (w, h) ->
      w *. h

let classify n =
  match n with
  | 0 -> "zero"
  | 1 -> "one"
  | _ -> "many"

let rec factorial n =
  if n <= 1 then
    1
  else
    n * factorial (n - 1)
