open Websharper_javascript
open Wsui

let () =
  let v = Var.create 0 in
  Var.set v 41;
  let _doc = Doc.append (Doc.text "hello ") (Doc.text "ui") in
  Console.log_2 (Printf.sprintf "v=%d" (Var.get v))
