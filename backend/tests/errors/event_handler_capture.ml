(* A server-rendered event handler is lifted to top level, so it must be closed
   (no captures from the enclosing scope). *)
open WebSharper_UI
open WebSharper_UI.Html

let page () =
  let v = Var.create "x" in
  div [ on.click (fun _ _ -> Var.set v "y") ] []
