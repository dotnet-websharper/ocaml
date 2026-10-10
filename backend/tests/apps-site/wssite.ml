open WebSharper_JavaScript
open WebSharper_UI
open WebSharper_UI.Html
open WebSharper_Server

(* M5: a sitelet with a typed-ish route, an RPC, and a server-rendered page. *)

let[@rpc] add a b = Async.return (a + b)

let home (_ : unit context) () =
  Content.page ~title:"Site"
    [ h1 [] [ Doc.text "Site" ]; p [] [ Doc.text "server-rendered" ] ]

let[@website] site =
  Sitelet.make
    (fun req -> if req.path = "/" && req.method_ = "GET" then Some () else None)
    (fun () -> "/")
    home
