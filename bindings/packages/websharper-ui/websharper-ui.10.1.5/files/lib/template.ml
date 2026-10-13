(* Hand-written overlay: the wsocaml templating runtime entry point,
   `WebSharper_UI.Template`. Generated template modules call
   `WebSharper_UI.Template.getOrLoad` with the raw source and typed holes; on
   the client this delegates to the WebSharper.UI template runtime. *)

type element = WebSharper_JavaScript.Element.t
type event = WebSharper_JavaScript.Event.t
type hole = TemplateHole.t

let text name (v : string) = TemplateHole.makeText name v
let view name (v : string View.t) = TemplateHole.makeTextView name v
let elt name (v : Doc.t) = TemplateHoleElt.create name v
let attr name (v : Attr.t) = TemplateHoleAttribute.create name v
let event name (f : element -> event -> unit) = TemplateHoleEvent.create name f
let afterRender name (f : element -> unit) =
  TemplateHoleAfterRender.create name f
let varStr name (v : string Var.t) = TemplateHole.makeVar name v
let varBool name (v : bool Var.t) = TemplateHole.makeVar_2 name v
let varFloat name (v : float Var.t) = TemplateHole.makeVar_8 name v

let getOrLoad ~base ~name ~src ~refs ~keep_unfilled (holes : hole list) : Doc.t =
  ignore refs;
  ignore keep_unfilled;
  let fopt = function
    | None -> WebSharper_StdLib.FSharpOption.none ()
    | Some x -> WebSharper_StdLib.FSharpOption.some x
  in
  ClientDoc.getOrLoadTemplate base (fopt name)
    (fun () -> DomUtility.parseHTMLIntoFakeRoot src)
    holes
