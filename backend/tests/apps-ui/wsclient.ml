open WebSharper_UI
open WebSharper_UI.Html

(* M4: a server-rendered page emits a placeholder for this client region
   (`<div id="app" data-ws-key="Main.app">`); the client runtime hydrates it by
   running this [@client] value, which renders the view into `#app`. *)

let[@client] app () =
  let v = Var.create "before" in
  let view =
    div
      [ On.click (fun _ _ -> Var.set v "after") ]
      [ Doc.textView (Var.view v) ]
  in
  Doc.runById "app" view
