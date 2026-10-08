open Websharper_javascript
open Websharper_ui

let () =
  let v = Var2.create_2 41 in
  Var.set_Value v 42;
  Console.log_2 (Printf.sprintf "v=%d" (Var.get_Value v))
