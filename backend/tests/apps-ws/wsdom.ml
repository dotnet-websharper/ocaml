(* A DOM example using the generated WebSharper.JavaScript bindings. The cyclic
   DOM type hierarchy is collapsed to a single abstract type (EventTarget.t), so
   no coercions are needed between Document/Element/Node/Event. *)

open WebSharper_JavaScript

let () =
  let window = Window.self () in
  let document : Document.t = Window.document window in
  let body : Node.t = Document.body document in

  let div : Element.t = Document.createElement document "div" in
  Element.set_id div "box";
  Element.set_className div "greeting";
  Element.set_innerHTML div "<b>hello</b>";
  ignore (Node.appendChild body div);

  Console.log ("tag=" ^ Element.tagName div);
  Console.log ("html=" ^ Element.innerHTML div);

  EventTarget.addEventListener div "ping" (Js.of_js (fun () ->
    Element.set_innerHTML div "pinged"));

  let found : Element.t = Document.getElementById document "box" in
  Console.log ("found=" ^ Element.id found)
