open WebSharper_JavaScript
open WebSharper_UI
open WebSharper_UI.Html
open WebSharper_Server

(* M5: a [@website] sitelet with an inferred (typed) router, an RPC,
   server-rendered pages, and a hydrated client region. *)

type endpoint =
  | Home [@endpoint "GET /"]
  | User of int [@endpoint "GET /user/@id"]

let[@rpc] add a b = Async.return (a + b)

let render (_ : endpoint context) ep =
  match ep with
  | Home ->
      Content.page ~title:"Site"
        [ h1 [] [ Doc.text "Site" ];
          p [] [ Doc.text "server-rendered" ];
          WebSharper_ClientServer.hydrate (fun () ->
              let v = Var.create "before" in
              div
                [ On.click (fun _ _ -> Var.set v "after") ]
                [ Doc.textView (Var.view v) ]) ]
  | User id ->
      Content.page ~title:"User" [ h1 [] [ Doc.text (Printf.sprintf "User %d" id) ] ]

let[@website] site = Sitelet.Infer render
