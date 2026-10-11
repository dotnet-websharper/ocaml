(* Generate the raw-FFI test fixture: a small set of OCaml binding modules for
   browser/JS globals (exercising the backend's raw FFI lowering: js:, jsnew:,
   jsget:, jsset:, jsm:, jsgp:, jssp:, jse:, jsdget, jsdset, ccall).

   Usage: gen_bindings [bindings-dir]   (default: bindings-legacy) *)

type member = string * string * string (* name, type, FFI scheme *)

let m name members = (name, "t", members, "")
let mt name members typename = (name, typename, members, "")
let mp name members typename prelude = (name, typename, members, prelude)

let reserved =
  [ "and"; "as"; "assert"; "begin"; "class"; "constraint"; "do"; "done"; "downto";
    "else"; "end"; "exception"; "external"; "false"; "for"; "fun"; "function";
    "functor"; "if"; "in"; "include"; "inherit"; "initializer"; "lazy"; "let";
    "match"; "method"; "module"; "mutable"; "new"; "object"; "of"; "open"; "or";
    "private"; "rec"; "sig"; "struct"; "then"; "to"; "true"; "try"; "type";
    "val"; "virtual"; "when"; "while"; "with"; "land"; "lor"; "lxor"; "lsl";
    "lsr"; "asr"; "mod" ]

let spec : (string * string * member list * string) list =
  [
    m "Event"
      [ ("event_type", "t -> string", "jsgp:type"); ("target", "t -> t", "jsgp:target");
        ("prevent_default", "t -> unit", "jsm:preventDefault");
        ("stop_propagation", "t -> unit", "jsm:stopPropagation") ];
    m "UiEvent"
      [ ("detail", "t -> int", "jsgp:detail"); ("view", "t -> t", "jsgp:view");
        ("which", "t -> int", "jsgp:which") ];
    m "MouseEvent"
      [ ("client_x", "t -> float", "jsgp:clientX"); ("client_y", "t -> float", "jsgp:clientY");
        ("page_x", "t -> float", "jsgp:pageX"); ("page_y", "t -> float", "jsgp:pageY");
        ("button", "t -> int", "jsgp:button"); ("ctrl_key", "t -> bool", "jsgp:ctrlKey");
        ("shift_key", "t -> bool", "jsgp:shiftKey") ];
    m "KeyboardEvent"
      [ ("key", "t -> string", "jsgp:key"); ("code", "t -> string", "jsgp:code");
        ("key_code", "t -> int", "jsgp:keyCode"); ("which", "t -> int", "jsgp:which");
        ("repeat", "t -> bool", "jsgp:repeat") ];
    m "Node"
      [ ("text_content", "t -> string", "jsgp:textContent");
        ("set_text_content", "t -> string -> unit", "jssp:textContent");
        ("child_nodes", "t -> t", "jsgp:childNodes"); ("parent_node", "t -> t", "jsgp:parentNode");
        ("append_child", "t -> t -> t", "jsm:appendChild");
        ("remove_child", "t -> t -> t", "jsm:removeChild");
        ("clone_node", "t -> bool -> t", "jsm:cloneNode");
        ("contains", "t -> t -> bool", "jsm:contains") ];
    mp "Element"
      [ ("tag_name", "t -> string", "jsgp:tagName"); ("id", "t -> string", "jsgp:id");
        ("set_id", "t -> string -> unit", "jssp:id"); ("inner_html", "t -> string", "jsgp:innerHTML");
        ("set_inner_html", "t -> string -> unit", "jssp:innerHTML");
        ("get_attribute", "t -> string -> string", "jsm:getAttribute");
        ("set_attribute", "t -> string -> string -> unit", "jsm:setAttribute");
        ("remove_attribute", "t -> string -> unit", "jsm:removeAttribute");
        ("query_selector", "t -> string -> t", "jsm:querySelector");
        ("add_event_listener", "t -> string -> (Event.t -> unit) -> unit", "jsm:addEventListener");
        ("remove_event_listener", "t -> string -> (Event.t -> unit) -> unit", "jsm:removeEventListener");
        ("dispatch_event", "t -> Event.t -> bool", "jsm:dispatchEvent") ]
      "t = Node.t" "";
    mp "HtmlElement"
      [ ("style", "t -> t", "jsgp:style"); ("inner_text", "t -> string", "jsgp:innerText");
        ("set_inner_text", "t -> string -> unit", "jssp:innerText"); ("click", "t -> unit", "jsm:click");
        ("offset_width", "t -> int", "jsgp:offsetWidth");
        ("offset_height", "t -> int", "jsgp:offsetHeight") ]
      "t = Node.t" "";
    mp "HtmlInputElement"
      [ ("value", "t -> string", "jsgp:value"); ("set_value", "t -> string -> unit", "jssp:value");
        ("checked", "t -> bool", "jsgp:checked"); ("set_checked", "t -> bool -> unit", "jssp:checked");
        ("placeholder", "t -> string", "jsgp:placeholder") ]
      "t = Node.t" "";
    mp "HtmlOptionElement"
      [ ("value", "t -> string", "jsgp:value"); ("set_value", "t -> string -> unit", "jssp:value");
        ("text", "t -> string", "jsgp:text"); ("set_text", "t -> string -> unit", "jssp:text");
        ("selected", "t -> bool", "jsgp:selected") ]
      "t = Node.t" "";
    mp "Document"
      [ ("create_element", "t -> string -> t", "jsm:createElement");
        ("create_text_node", "t -> string -> t", "jsm:createTextNode");
        ("get_element_by_id", "t -> string -> t", "jsm:getElementById");
        ("query_selector", "t -> string -> t", "jsm:querySelector"); ("body", "t -> t", "jsgp:body") ]
      "t = Node.t" "";
    m "Storage"
      [ ("length", "t -> int", "jsgp:length"); ("get_item", "t -> string -> Js.t", "jsm:getItem");
        ("set_item", "t -> string -> string -> unit", "jsm:setItem");
        ("remove_item", "t -> string -> unit", "jsm:removeItem") ];
    m "Window"
      [ ("get", "unit -> t", "jsget:window"); ("document", "t -> Document.t", "jsgp:document");
        ("local_storage", "t -> Storage.t", "jsgp:localStorage");
        ("inner_width", "t -> int", "jsgp:innerWidth");
        ("on_click", "t -> (MouseEvent.t -> unit) -> unit", "jse:click");
        ("on_keydown", "t -> (KeyboardEvent.t -> unit) -> unit", "jse:keydown") ];
    m "Url"
      [ ("create", "string -> t", "jsnew:URL"); ("href", "t -> string", "jsgp:href");
        ("host", "t -> string", "jsgp:host"); ("hostname", "t -> string", "jsgp:hostname");
        ("pathname", "t -> string", "jsgp:pathname"); ("search", "t -> string", "jsgp:search");
        ("hash", "t -> string", "jsgp:hash"); ("to_string", "t -> string", "jsm:toString") ];
    m "TextEncoder"
      [ ("create", "unit -> t", "jsnew0:TextEncoder"); ("encoding", "t -> string", "jsgp:encoding");
        ("encode", "t -> string -> t", "jsm:encode") ];
    mt "Json" [ ("parse", "string -> value", "js:JSON.parse"); ("stringify", "value -> string", "js:JSON.stringify") ] "value = Js.t";
    m "JsDate"
      [ ("now", "unit -> float", "js0:Date.now"); ("create", "unit -> t", "jsnew0:Date");
        ("get_time", "t -> float", "jsm:getTime"); ("get_full_year", "t -> int", "jsm:getFullYear");
        ("get_month", "t -> int", "jsm:getMonth"); ("get_date", "t -> int", "jsm:getDate");
        ("to_iso_string", "t -> string", "jsm:toISOString") ];
    m "JsArray"
      [ ("create", "unit -> t", "jsnew0:Array"); ("length", "t -> int", "jsgp:length");
        ("get", "t -> int -> Js.t", "jsdget"); ("set", "t -> int -> Js.t -> unit", "jsdset");
        ("push", "t -> Js.t -> int", "jsm:push"); ("pop", "t -> Js.t", "jsm:pop");
        ("join", "t -> string -> string", "jsm:join"); ("slice", "t -> int -> int -> t", "jsm:slice") ];
    mt "Console"
      [ ("log", "string -> unit", "js:console.log"); ("error", "string -> unit", "js:console.error");
        ("warn", "string -> unit", "js:console.warn"); ("info", "string -> unit", "js:console.info") ]
      "t = Js.t";
    mt "Math"
      [ ("max", "float -> float -> float", "js:Math.max"); ("min", "float -> float -> float", "js:Math.min");
        ("abs", "float -> float", "js:Math.abs"); ("sqrt", "float -> float", "js:Math.sqrt");
        ("floor", "float -> float", "js:Math.floor"); ("round", "float -> float", "js:Math.round");
        ("pi", "unit -> float", "jsget:Math.PI") ]
      "";
  ]

let coercions name =
  match name with
  | "UiEvent" -> [ ("as_event", "t -> Event.t"); ("of_event", "Event.t -> t") ]
  | "MouseEvent" ->
      [ ("as_ui_event", "t -> UiEvent.t"); ("of_ui_event", "UiEvent.t -> t");
        ("as_event", "t -> Event.t"); ("of_event", "Event.t -> t") ]
  | "KeyboardEvent" -> [ ("as_event", "t -> Event.t"); ("of_event", "Event.t -> t") ]
  | _ -> []

let lower_first s = if s = "" then s else String.uncapitalize_ascii s

let ljust s w = s ^ String.make (max 0 (w - String.length s)) ' '

let emit dir (name, typename, members, prelude) =
  let typename = if coercions name <> [] then "t" else typename in
  let b = Buffer.create 256 in
  Buffer.add_string b "(* Generated by frontend/bin/gen_bindings.ml. Do not edit. *)\n";
  if prelude <> "" then Buffer.add_string b (prelude ^ "\n");
  if typename = "t" then (
    Buffer.add_string b "type t\n";
    Buffer.add_string b "external as_js : t -> Js.t = \"%identity\"\n";
    Buffer.add_string b "external of_js : Js.t -> t = \"%identity\"\n")
  else if typename <> "" then Buffer.add_string b (Printf.sprintf "type %s\n" typename);
  List.iter
    (fun (fname, fsig) -> Buffer.add_string b (Printf.sprintf "external %s : %s = \"%%identity\"\n" fname fsig))
    (coercions name);
  let w = List.fold_left (fun a (n, _, _) -> max a (String.length n)) 0 members in
  List.iter
    (fun (mname, mtype, scheme) ->
      let mname = if List.mem mname reserved then mname ^ "_" else mname in
      Buffer.add_string b (Printf.sprintf "external %s : %s = \"%s\"\n" (ljust mname w) mtype scheme))
    members;
  let path = Filename.concat dir (lower_first name ^ ".ml") in
  let oc = open_out path in
  output_string oc (Buffer.contents b);
  close_out oc

let () =
  let dir = if Array.length Sys.argv > 1 then Sys.argv.(1) else "bindings-legacy" in
  (try Sys.mkdir dir 0o755 with Sys_error _ -> ());
  List.iter (emit dir) spec;
  Printf.printf "wrote %d binding modules to %s\n" (List.length spec) dir
