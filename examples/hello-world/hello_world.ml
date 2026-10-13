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

(* WebSharper.UI.Notation-style `Var` operators. (WS's own `Notation.(:=)`/`(!)`
   are F# SRTP-inline and do not lower through wsocaml, so define them here over
   the real `Var.get`/`Var.set`.) *)
module Notation = struct
  let ( := ) (v : 'a Var.t) (x : 'a) = Var.set v x
  let ( ! ) (v : 'a Var.t) = Var.get v
end

open Notation

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
                   let c = e.vars.counter in
                   c := !c +. 1.)
              |> Greeting.doc)
          ]
  )
