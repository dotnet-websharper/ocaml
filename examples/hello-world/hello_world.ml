(* A minimal wsocaml server: a sitelet with a single Home page, served natively
   by WebSharper_Server (websharper-server) using the WebSharper_UI shadow
   (websharper-ui-server). *)

open WebSharper_UI
open WebSharper_UI.Html
open WebSharper_Server

let home (_ : unit context) () =
  Content.page ~title:"Hello, world!"
    [ h1 [] [ Doc.text "Hello, world!" ];
      p [] [ Doc.text "Served by websharper-server." ] ]

let site = Sitelet.content "GET" "/" home

let () = Server.serve ~port:8080 site
