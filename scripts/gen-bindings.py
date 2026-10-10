#!/usr/bin/env python3
"""Generate the raw-FFI test fixture: a small set of OCaml binding modules for
browser/JS globals.

These bindings exist to exercise the backend's **raw FFI lowering** (`js:`,
`jsnew:`, `jsget:`, `jsset:`, `jsm:`, `jsgp:`, `jssp:`, `jse:`, `jsdget`,
`jsdset`, `ccall`), independently of the WebSharper `ws:` addresses that the
generated packages (`bindings/`) use. The bulk of the browser surface is covered
by the generated `websharper-javascript` package; only what the `jsbind`/`dom`
emit tests need is kept here.

Each module is a set of `external`s over `Js.t` (an opaque JS handle). Schemes:
  js:<path>        global call        (path dotted, e.g. Math.max)
  js0:<path>       global call, no args
  jsnew:<path>     global new
  jsnew0:<path>    global new, no args
  jsget:<path>     global property get
  jsset:<path>     global property set
  jsm:<name>       receiver method call     (receiver = first arg)
  jsgp:<name>      receiver property get
  jssp:<name>      receiver property set
  jse:<event>      receiver event listener  (addEventListener)
Usage: gen-bindings.py [bindings-dir]
"""
import os
import sys

DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "bindings-legacy")


def M(name, members, typename="t", prelude=""):
    return (name, typename, members, prelude)


RESERVED = {
    "and", "as", "assert", "begin", "class", "constraint", "do", "done",
    "downto", "else", "end", "exception", "external", "false", "for", "fun",
    "function", "functor", "if", "in", "include", "inherit", "initializer",
    "lazy", "let", "match", "method", "module", "mutable", "new", "object",
    "of", "open", "or", "private", "rec", "sig", "struct", "then", "to",
    "true", "try", "type", "val", "virtual", "when", "while", "with",
    "land", "lor", "lxor", "lsl", "lsr", "asr", "mod",
}


SPEC = [
    M("Event", [
        ("event_type", "t -> string", "jsgp:type"),
        ("target", "t -> t", "jsgp:target"),
        ("prevent_default", "t -> unit", "jsm:preventDefault"),
        ("stop_propagation", "t -> unit", "jsm:stopPropagation"),
    ]),
    M("UiEvent", [
        ("detail", "t -> int", "jsgp:detail"),
        ("view", "t -> t", "jsgp:view"),
        ("which", "t -> int", "jsgp:which"),
    ]),
    M("MouseEvent", [
        ("client_x", "t -> float", "jsgp:clientX"),
        ("client_y", "t -> float", "jsgp:clientY"),
        ("page_x", "t -> float", "jsgp:pageX"),
        ("page_y", "t -> float", "jsgp:pageY"),
        ("button", "t -> int", "jsgp:button"),
        ("ctrl_key", "t -> bool", "jsgp:ctrlKey"),
        ("shift_key", "t -> bool", "jsgp:shiftKey"),
    ]),
    M("KeyboardEvent", [
        ("key", "t -> string", "jsgp:key"),
        ("code", "t -> string", "jsgp:code"),
        ("key_code", "t -> int", "jsgp:keyCode"),
        ("which", "t -> int", "jsgp:which"),
        ("repeat", "t -> bool", "jsgp:repeat"),
    ]),
    M("Node", [
        ("text_content", "t -> string", "jsgp:textContent"),
        ("set_text_content", "t -> string -> unit", "jssp:textContent"),
        ("child_nodes", "t -> t", "jsgp:childNodes"),
        ("parent_node", "t -> t", "jsgp:parentNode"),
        ("append_child", "t -> t -> t", "jsm:appendChild"),
        ("remove_child", "t -> t -> t", "jsm:removeChild"),
        ("clone_node", "t -> bool -> t", "jsm:cloneNode"),
        ("contains", "t -> t -> bool", "jsm:contains"),
    ]),
    M("Element", [
        ("tag_name", "t -> string", "jsgp:tagName"),
        ("id", "t -> string", "jsgp:id"),
        ("set_id", "t -> string -> unit", "jssp:id"),
        ("inner_html", "t -> string", "jsgp:innerHTML"),
        ("set_inner_html", "t -> string -> unit", "jssp:innerHTML"),
        ("get_attribute", "t -> string -> string", "jsm:getAttribute"),
        ("set_attribute", "t -> string -> string -> unit", "jsm:setAttribute"),
        ("remove_attribute", "t -> string -> unit", "jsm:removeAttribute"),
        ("query_selector", "t -> string -> t", "jsm:querySelector"),
        ("add_event_listener", "t -> string -> (Event.t -> unit) -> unit", "jsm:addEventListener"),
        ("remove_event_listener", "t -> string -> (Event.t -> unit) -> unit", "jsm:removeEventListener"),
        ("dispatch_event", "t -> Event.t -> bool", "jsm:dispatchEvent"),
    ], "t = Node.t"),
    M("HtmlElement", [
        ("style", "t -> t", "jsgp:style"),
        ("inner_text", "t -> string", "jsgp:innerText"),
        ("set_inner_text", "t -> string -> unit", "jssp:innerText"),
        ("click", "t -> unit", "jsm:click"),
        ("offset_width", "t -> int", "jsgp:offsetWidth"),
        ("offset_height", "t -> int", "jsgp:offsetHeight"),
    ], "t = Node.t"),
    M("HtmlInputElement", [
        ("value", "t -> string", "jsgp:value"),
        ("set_value", "t -> string -> unit", "jssp:value"),
        ("checked", "t -> bool", "jsgp:checked"),
        ("set_checked", "t -> bool -> unit", "jssp:checked"),
        ("placeholder", "t -> string", "jsgp:placeholder"),
    ], "t = Node.t"),
    M("HtmlOptionElement", [
        ("value", "t -> string", "jsgp:value"),
        ("set_value", "t -> string -> unit", "jssp:value"),
        ("text", "t -> string", "jsgp:text"),
        ("set_text", "t -> string -> unit", "jssp:text"),
        ("selected", "t -> bool", "jsgp:selected"),
    ], "t = Node.t"),
    M("Document", [
        ("create_element", "t -> string -> t", "jsm:createElement"),
        ("create_text_node", "t -> string -> t", "jsm:createTextNode"),
        ("get_element_by_id", "t -> string -> t", "jsm:getElementById"),
        ("query_selector", "t -> string -> t", "jsm:querySelector"),
        ("body", "t -> t", "jsgp:body"),
    ], "t = Node.t"),
    M("Storage", [
        ("length", "t -> int", "jsgp:length"),
        ("get_item", "t -> string -> Js.t", "jsm:getItem"),
        ("set_item", "t -> string -> string -> unit", "jsm:setItem"),
        ("remove_item", "t -> string -> unit", "jsm:removeItem"),
    ]),
    M("Window", [
        ("get", "unit -> t", "jsget:window"),
        ("document", "t -> Document.t", "jsgp:document"),
        ("local_storage", "t -> Storage.t", "jsgp:localStorage"),
        ("inner_width", "t -> int", "jsgp:innerWidth"),
        ("on_click", "t -> (MouseEvent.t -> unit) -> unit", "jse:click"),
        ("on_keydown", "t -> (KeyboardEvent.t -> unit) -> unit", "jse:keydown"),
    ]),
    M("Url", [
        ("create", "string -> t", "jsnew:URL"),
        ("href", "t -> string", "jsgp:href"),
        ("host", "t -> string", "jsgp:host"),
        ("hostname", "t -> string", "jsgp:hostname"),
        ("pathname", "t -> string", "jsgp:pathname"),
        ("search", "t -> string", "jsgp:search"),
        ("hash", "t -> string", "jsgp:hash"),
        ("to_string", "t -> string", "jsm:toString"),
    ]),
    M("TextEncoder", [
        ("create", "unit -> t", "jsnew0:TextEncoder"),
        ("encoding", "t -> string", "jsgp:encoding"),
        ("encode", "t -> string -> t", "jsm:encode"),
    ]),
    M("Json", [
        ("parse", "string -> value", "js:JSON.parse"),
        ("stringify", "value -> string", "js:JSON.stringify"),
    ], "value = Js.t"),
    M("JsDate", [
        ("now", "unit -> float", "js0:Date.now"),
        ("create", "unit -> t", "jsnew0:Date"),
        ("get_time", "t -> float", "jsm:getTime"),
        ("get_full_year", "t -> int", "jsm:getFullYear"),
        ("get_month", "t -> int", "jsm:getMonth"),
        ("get_date", "t -> int", "jsm:getDate"),
        ("to_iso_string", "t -> string", "jsm:toISOString"),
    ]),
    M("JsArray", [
        ("create", "unit -> t", "jsnew0:Array"),
        ("length", "t -> int", "jsgp:length"),
        ("get", "t -> int -> Js.t", "jsdget"),
        ("set", "t -> int -> Js.t -> unit", "jsdset"),
        ("push", "t -> Js.t -> int", "jsm:push"),
        ("pop", "t -> Js.t", "jsm:pop"),
        ("join", "t -> string -> string", "jsm:join"),
        ("slice", "t -> int -> int -> t", "jsm:slice"),
    ]),
    M("Console", [
        ("log", "string -> unit", "js:console.log"),
        ("error", "string -> unit", "js:console.error"),
        ("warn", "string -> unit", "js:console.warn"),
        ("info", "string -> unit", "js:console.info"),
    ], "t = Js.t"),
    M("Math", [
        ("max", "float -> float -> float", "js:Math.max"),
        ("min", "float -> float -> float", "js:Math.min"),
        ("abs", "float -> float", "js:Math.abs"),
        ("sqrt", "float -> float", "js:Math.sqrt"),
        ("floor", "float -> float", "js:Math.floor"),
        ("round", "float -> float", "js:Math.round"),
        ("pi", "unit -> float", "jsget:Math.PI"),
    ], "", ""),
]


def emit(name, typename, members, prelude):
    lines = ["(* Generated by scripts/gen-bindings.py. Do not edit. *)"]
    if prelude:
        lines.append(prelude)
    if typename == "t":
        lines.append("type t")
        lines.append('external as_js : t -> Js.t = "%identity"')
        lines.append('external of_js : Js.t -> t = "%identity"')
    elif typename:
        lines.append("type %s" % typename)
    for fname, fsig in COERCIONS.get(name, []):
        lines.append('external %s : %s = "%%identity"' % (fname, fsig))
    wide = max((len(m[0]) for m in members), default=0)
    for mname, mtype, scheme in members:
        if mname in RESERVED:
            mname = mname + "_"
        lines.append('external %s : %s = "%s"' % (mname.ljust(wide), mtype, scheme))
    path = os.path.join(DIR, name[0].lower() + name[1:] + ".ml")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


COERCIONS = {
    "UiEvent": [("as_event", "t -> Event.t"), ("of_event", "Event.t -> t")],
    "MouseEvent": [("as_ui_event", "t -> UiEvent.t"), ("of_ui_event", "UiEvent.t -> t"),
                   ("as_event", "t -> Event.t"), ("of_event", "Event.t -> t")],
    "KeyboardEvent": [("as_event", "t -> Event.t"), ("of_event", "Event.t -> t")],
}


def main():
    os.makedirs(DIR, exist_ok=True)
    for name, typename, members, prelude in SPEC:
        if name in COERCIONS:
            typename = "t"
        emit(name, typename, members, prelude)
    print("wrote %d binding modules to %s" % (len(SPEC), DIR))


if __name__ == "__main__":
    main()
