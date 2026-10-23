open WebSharper_JavaScript
open WebSharper_UI
open WebSharper_UI.Html
open WebSharper_ClientServer
open WebSharper_Server

(* M5: a [@website] sitelet with an inferred (typed) router, an RPC,
   server-rendered pages, a hydrated client region, and a server-rendered
   element with a client event handler. *)

type endpoint =
  | Home [@endpoint "GET /"]
  | User of int [@endpoint "GET /user/@0"]
  | Echo of { msg : string } [@endpoint "GET /echo/@msg"]
  | Item of { id : int; slug : string } [@endpoint "GET /item/@slug/@id"]
  | Search of { q : string; page : int } [@endpoint "GET /search?q=@q&page=@page"]

let[@rpc] add a b = Async.return (a + b)

let[@website] main =
  Sitelet.infer (fun (ctx : endpoint context) ep ->
    match ep with
    | Home ->
        Content.page
          ~title:"Site"
          [
            h1 [] [text "Site"];
            p [] [text "server-rendered"];
            hydrate (fun () ->
              let v = Var.create "before" in

              div [
                  on.click (fun _ _ -> Var.set v "after")
              ] [
                  textView (Var.view v)
              ]
            );
            button
              [ on.click (fun el _ -> Element.setAttribute el "data-clicked" "yes") ]
              [ text "click me" ]
          ]
    | User id ->
        Content.page
          ~title:"User"
          [
            h1 [] [text (Printf.sprintf "User %d" id)];
            p [] [text (Printf.sprintf "link=%s" (ctx.link (Echo { msg = "hi" })))]
          ]
    | Echo e -> Content.text (Printf.sprintf "Echo:%s" e.msg)
    | Item i ->
        Content.text
          (Printf.sprintf "Item:%s:%d link=%s" i.slug i.id
             (ctx.link (Item { id = i.id; slug = i.slug })))
    | Search s ->
        Content.text
          (Printf.sprintf "Search:%s:%d link=%s" s.q s.page (ctx.link (User s.page)))
  )
