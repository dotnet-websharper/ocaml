let () =
  let w = Window.get () in
  let doc = Window.document w in
  let el = Document.create_element doc "div" in
  Node.set_text_content el "hello";
  Element.set_attribute el "id" "box";
  ignore (Node.append_child (Document.body doc) el);
  let inp = Document.create_element doc "input" in
  HtmlInputElement.set_value inp "typed";
  ignore (Node.append_child (Document.body doc) inp);
  let sel = Document.create_element doc "select" in
  let opt = Document.create_element doc "option" in
  HtmlOptionElement.set_value opt "opt1";
  HtmlOptionElement.set_text opt "Option 1";
  ignore (Node.append_child sel opt);
  ignore (Node.append_child (Document.body doc) sel);
  Storage.set_item (Window.local_storage w) "k" "v";
  Console.log ("url host=" ^ Url.host (Url.create "http://example.com/path?x=1#h"));
  let encoded =
    (Js.of_js (Js.get (TextEncoder.as_js (TextEncoder.encode (TextEncoder.create ()) "hello")) "length") : int) in
  Console.log (Printf.sprintf "encoded=%d" encoded);
  Element.add_event_listener el "ping" (fun _ -> Console.log "ping received");
  Window.on_click w (fun e ->
      Console.log (Printf.sprintf "clicked %g,%g" (MouseEvent.client_x e) (MouseEvent.client_y e)));
  Window.on_keydown w (fun e -> Console.log ("key=" ^ KeyboardEvent.key e))
