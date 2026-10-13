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
        Content.page
          ~title:"Hello, world!"
          [
            hydrate (fun () ->
              Greeting.create ()
              |> Greeting.title "Hello, world!"
              |> Greeting.body "Served by websharper-server, rendered from a template."
              |> Greeting.onIncrement_withModel (fun e ->
                   Var.update e.vars.counter (fun n -> n +. 1.))
              |> Greeting.doc)
          ]
  )
