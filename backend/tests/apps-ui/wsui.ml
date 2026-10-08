open WebSharper_JavaScript
open WebSharper_UI

let () =
  let v = Var.create 0 in
  Var.set v 41;
  (* macro: expands to the TemplateHoleModule.Text constructor (no DOM needed) *)
  let _ = TemplateHole.makeText "a" "b" in
  Console.log (Printf.sprintf "v=%d" (Var.get v))
