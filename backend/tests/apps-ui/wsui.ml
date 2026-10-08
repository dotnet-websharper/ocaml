open Websharper_javascript

let () =
  let v = Websharper_ui.Var.create 0 in
  Websharper_ui.Var.set v 41;
  (* macro: expands to the TemplateHoleModule.Text constructor (no DOM needed) *)
  let _ = Websharper_ui.TemplateHole.makeText "a" "b" in
  Console.log (Printf.sprintf "v=%d" (Websharper_ui.Var.get v))
