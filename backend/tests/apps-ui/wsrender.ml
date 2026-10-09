open WebSharper_StdLib
open WebSharper_JavaScript
open WebSharper_UI

(* A reactive view: a click handler updates a Var, and a textView bound to its
   View re-renders the DOM. Exercises rendering, event handling, and the
   reactive update scheduler. *)
let () =
  let v = Var.create "before" in
  let view =
    Doc.element "div"
      (SeqModule.ofArray [| On.click (fun _ _ -> Var.set v "after") |])
      (SeqModule.ofArray [| Doc.textView (Var.view v) |])
  in
  Doc.runById "root" view
