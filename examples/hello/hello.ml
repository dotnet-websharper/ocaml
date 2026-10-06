type shape = Circle of float | Rectangle of float * float

let square x = x * x
let twice f x = f (f x)
let classify = function
  | Circle r -> r *. r
  | Rectangle (w, h) -> w *. h

let answer = twice square 2
