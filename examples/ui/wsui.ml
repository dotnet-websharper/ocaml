(* Tier-1 facade over WebSharper.UI: mirrors the WebSharper API surface as
   OCaml modules (Var / View / Doc), built on the non-macro members of the
   generated websharper-ui bindings. *)

module View = struct
  type 'a t = 'a Websharper_ui.View.t

  let map (f: 'a -> 'b) (v: 'a t) : 'b t =
    Websharper_ui.View.map v (Js.of_js f)
end

module Var = struct
  type 'a t = 'a Websharper_ui.Var.t

  let create (x: 'a) : 'a t = Websharper_ui.Var2.create_2 x
  let get (v: 'a t) : 'a = Websharper_ui.Var.get_Value v
  let set (v: 'a t) (x: 'a) : unit = Websharper_ui.Var.set_Value v x
  let view (v: 'a t) : 'a View.t = Websharper_ui.Var.get_View v
end

module Doc = struct
  type t = Websharper_ui.Doc.t

  let text (s: string) : t = Websharper_ui.Doc.textNode s
  let empty () : t = Websharper_ui.Doc.get_Empty ()
  let append (a: t) (b: t) : t = Websharper_ui.Doc.append a b
  let text_view (v: string View.t) : t = Websharper_ui.Doc.textView v
  let run_by_id (id: string) (d: t) : unit = Websharper_ui.Doc.runById id d
end
