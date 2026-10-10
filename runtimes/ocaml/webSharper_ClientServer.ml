(* Native (server-side) implementation of WebSharper_ClientServer. The compiler
   expands `client`/`hydrate` into `__client`/`__hydrate` with a stable id. *)

let region id children = [ Ssr.el "div" [ ("id", id); ("data-ws-key", id) ] children ]
let __client id = region id []
let __hydrate id f = region id (f ())
let client _ = failwith "WebSharper_ClientServer.client is expanded by the compiler"
let hydrate _ = failwith "WebSharper_ClientServer.hydrate is expanded by the compiler"
