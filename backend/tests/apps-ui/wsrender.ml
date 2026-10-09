open WebSharper_UI
open WebSharper_UI.Html

(* A reactive view built with the WebSharper.UI HTML combinators: attributes and
   inner nodes are plain OCaml lists. *)
let () =
  let v = Var.create "before" in
  let view =
    div
      [ On.click (fun _ _ -> Var.set v "after") ]
      [ Doc.textView (Var.view v) ]
  in
  Doc.runById "root" view
