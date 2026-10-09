open WebSharper_JavaScript
open WebSharper_UI
open WebSharper_UI.Html

(* Build the DOM with the WebSharper.UI HTML combinators, then verify and
   interact with it through the WebSharper.JavaScript DOM bindings. *)
let () =
  let view =
    div
      [ Attr.create "id" "box"; Attr.create "class" "greeting" ]
      [ b [] [ Doc.text "hello" ] ]
  in
  Doc.runById "root" view;

  let document : Document.t = Window.document (Window.self ()) in
  let box : Element.t = Document.getElementById document "box" in
  Console.log ("tag=" ^ Element.tagName box);
  Console.log ("html=" ^ Element.innerHTML box);

  EventTarget.addEventListener box "ping" (Js.of_js (fun () ->
    Element.set_innerHTML box "pinged"));

  Console.log ("found=" ^ Element.id box)
