(* Tier-1 facade over WebSharper.UI: a small, ergonomic OCaml surface built on
   the non-macro members of the generated websharper-ui bindings. *)

type 'a var = 'a Websharper_ui.Var.t
type 'a view = 'a Websharper_ui.View.t
type doc = Websharper_ui.Doc.t

let create (x: 'a) : 'a var = Websharper_ui.Var2.create_2 x
let get (v: 'a var) : 'a = Websharper_ui.Var.get_Value v
let set (v: 'a var) (x: 'a) : unit = Websharper_ui.Var.set_Value v x
let view (v: 'a var) : 'a view = Websharper_ui.Var.get_View v

let map (f: 'a -> 'b) (v: 'a view) : 'b view =
  Websharper_ui.View.map v (Js.of_js f)

let text (s: string) : doc = Websharper_ui.Doc.textNode s
let empty () : doc = Websharper_ui.Doc.get_Empty ()
let append (a: doc) (b: doc) : doc = Websharper_ui.Doc.append a b
let text_view (v: string view) : doc = Websharper_ui.Doc.textView v
let run_by_id (id: string) (d: doc) : unit = Websharper_ui.Doc.runById id d
