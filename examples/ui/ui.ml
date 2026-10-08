open WebSharper_JavaScript
open WebSharper_UI

(* The generic Var and its static-helper Var are merged into one module, so
   Var.create/Var.set/Var.get all live under Var. *)
let () =
  let v = Var.create 0 in
  Var.set v 41;
  (* macro: expands to the TemplateHoleModule.Text constructor *)
  let _macro = TemplateHole.makeText "a" "b" in
  let _ = Doc.append (Doc.text "hello ") (Doc.text "ui") in
  Console.log (Printf.sprintf "v=%d" (Var.get v))
