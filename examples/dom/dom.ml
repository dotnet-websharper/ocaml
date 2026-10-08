(* A DOM example using the generated WebSharper.JavaScript bindings. The cyclic
   DOM type hierarchy is collapsed to a single abstract type (EventTarget.t), so
   no coercions are needed between Document/Element/Node/Event. *)

open WebSharper_JavaScript

let () =
  let window = Window.get_Self () in
  let document : Document.t = Window.get_Document window in
  let body : Node.t = Document.get_Body document in

  let div : Element.t = Document.createElement document "div" in
  Element.set_Id div "box";
  Element.set_ClassName div "greeting";
  Element.set_InnerHTML div "<b>hello</b>";
  ignore (Node.appendChild body div);

  Console.log ("tag=" ^ Element.get_TagName div);
  Console.log ("html=" ^ Element.get_InnerHTML div);

  EventTarget.addEventListener div "ping" (Js.of_js (fun () ->
    Element.set_InnerHTML div "pinged"));

  let found : Element.t = Document.getElementById document "box" in
  Console.log ("found=" ^ Element.get_Id found)
