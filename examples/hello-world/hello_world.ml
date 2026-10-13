open WebSharper_JavaScript
open WebSharper_UI
open WebSharper_UI.Html
open WebSharper_ClientServer
open WebSharper_Server

(* A DU-based sitelet: the endpoint is a variant whose cases carry
   [@endpoint "METHOD /path"]; `Sitelet.infer` gets a router/URL builder
   generated from it. The Home page embeds a hydrated client-side piece. *)

type endpoint =
  | Home [@endpoint "GET /"]

module Greeting = [%template "views/greeting.html"]

let[@website] main =
  Sitelet.infer (fun (_ : endpoint context) ep ->
    match ep with
    | Home ->
        let greeting =
          Greeting.create ()
          |> Greeting.title "Hello, world!"
          |> Greeting.body "Served by websharper-server, rendered from a template."
          |> Greeting.onIncrement_withModel (fun e ->
               Var.set e.vars.counter (Var.get e.vars.counter +. 1.))
          |> Greeting.doc
        in
        Content.page
          ~title:"Hello, world!"
          [
            greeting;
            hydrate (fun () ->
              let v = Var.create "before" in
              div [
                  on.click (fun _ _ -> Var.set v "after")
              ] [
                  textView (Var.view v)
              ]
            )
          ]
  )
