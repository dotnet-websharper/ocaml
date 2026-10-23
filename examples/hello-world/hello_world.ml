open WebSharper_JavaScript
open WebSharper_UI
open WebSharper_UI.Html
open WebSharper_UI.Notation
open WebSharper_ClientServer
open WebSharper_Server

(* A DU-based sitelet: the endpoint is a variant whose cases carry
   [@endpoint "METHOD /path"]; `Sitelet.infer` gets a router/URL builder
   generated from it. The Home page embeds a hydrated client-side piece. *)

type endpoint =
  | Home [@endpoint "GET /"]
  | Echo of { msg:string } [@endpoint "GET /echo/@msg"]
  
module Greeting = [%template "views/greeting.html"]

let[@website] main =
  Sitelet.infer (fun (_ : endpoint context) ep ->
    match ep with
    | Home ->
        Content.page
          ~title:"Hello, world!"
          [
            div [
              on.click (fun _ _ -> Console.log "Adam!")
            ] [text "Click me!"];
            hydrate (fun () ->
              Greeting.create ()
              |> Greeting.title "Hello, world!"
              |> Greeting.body "Served by websharper-server, rendered from a websharper-ui template."
              |> Greeting.onIncrement_withModel (fun e ->
                  (* Var: update syntax *)
                  e.vars.counter <~ (fun i -> i +. 1.)
              )
              |> Greeting.onDecrement_withModel (fun e ->
                  (* Var: assignment syntax *)
                   e.vars.counter := !(e.vars.counter) -. 1.
              )
              |> Greeting.doc)
          ]
    | Echo msg ->
        Content.text (Printf.sprintf "Hello:%s" msg.msg)
  )
