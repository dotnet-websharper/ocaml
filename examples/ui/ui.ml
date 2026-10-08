open Websharper_javascript

(* Uses the generated websharper-ui bindings directly: the generic Var and its
   static-helper Var were merged into one module, so Var.create/Var.set/Var.get
   all live under Websharper_ui.Var. *)
let () =
  let v = Websharper_ui.Var.create 0 in
  Websharper_ui.Var.set v 41;
  let _ = Websharper_ui.Doc.append
            (Websharper_ui.Doc.text "hello ")
            (Websharper_ui.Doc.text "ui") in
  Console.log (Printf.sprintf "v=%d" (Websharper_ui.Var.get v))
