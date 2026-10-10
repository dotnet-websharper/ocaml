open WebSharper_JavaScript
open WebSharper_UI
open WebSharper_UI.Html
open WebSharper_Server

(* A DU-based sitelet: the endpoint is a variant whose cases carry
   [@endpoint "METHOD /path"]; `Sitelet.Infer` gets a router/URL builder
   generated from it. The Home page embeds a hydrated client-side piece. *)

type endpoint =
  | Home [@endpoint "GET /"]

let render (_ : endpoint context) ep =
  match ep with
  | Home ->
      Content.page ~title:"Hello, world!"
        [ h1 [] [ Doc.text "Hello, world!" ];
          p [] [ Doc.text "Served by websharper-server, hydrated by WebSharper.UI." ];
          WebSharper_ClientServer.hydrate (fun () ->
              let v = Var.create "before" in
              div
                [ On.click (fun _ _ -> Var.set v "after") ]
                [ Doc.textView (Var.view v) ]) ]

let[@website] site = Sitelet.Infer render
