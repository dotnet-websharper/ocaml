(* A DOM example using the generated WebSharper.JavaScript bindings.
   Cross-module references in the generated bindings are opaque (Js.t) where
   the DOM type graph is cyclic, so we coerce explicitly here:
     Js.of_js : 'a -> Js.t      Js.to_js : Js.t -> 'a *)

let node_of (x: Js.t) : Node.t = Js.to_js x
let element_of (x: Js.t) : Element.t = Js.to_js x
let event_target_of (x: Js.t) : EventTarget.t = Js.to_js x

let () =
  let window = Window.get_Self () in
  let document : Document.t = Js.to_js (Window.get_Document window) in
  let body : Node.t = node_of (Document.get_Body document) in

  let div : Element.t = element_of (Document.createElement document "div") in
  Element.set_Id div "box";
  Element.set_ClassName div "greeting";
  Element.set_InnerHTML div "<b>hello</b>";
  ignore (Node.appendChild body (node_of (Js.of_js div)));

  Console.log_2 ("tag=" ^ Element.get_TagName div);
  Console.log_2 ("html=" ^ Element.get_InnerHTML div);

  let target = event_target_of (Js.of_js div) in
  EventTarget.addEventListener_3 target "ping" (Js.of_js (fun () ->
    Element.set_InnerHTML div "pinged"));

  let found : Element.t = element_of (Document.getElementById document "box") in
  Console.log_2 ("found=" ^ Element.get_Id found)
