open WebSharper_JavaScript

(* A small OCaml "library" whose [@export]ed API is called from plain JS. Values
   use the external representation: records -> objects, variants ->
   {"$":...,"$0":...}, lists -> arrays. *)

type point = { x : int; y : int }
type shape = Dot | Circle of int | Rect of point * point

let[@export] add a b = a + b

let[@export] label = "wlib"

let[@export] move (p : point) = { p with x = p.x + 10 }

let[@export] area (s : shape) =
  match s with
  | Dot -> 0
  | Circle r -> 3 * r * r
  | Rect (a, b) -> (b.x - a.x) * (b.y - a.y)

let[@export] total (xs : int list) = Stdlib.List.fold_left ( + ) 0 xs

let () = Console.log "wlib loaded"
