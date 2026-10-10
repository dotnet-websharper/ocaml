(* Client-side / hydrated fragments for server-rendered pages.

   `client` renders on the client into a placeholder; `hydrate` is also
   server-rendered and re-initialized on the client. Both take a `unit -> Doc`.
   The frontend lifts the argument into a client binding (stable `ws<id>`) and
   replaces the call with `__client`/`__hydrate`, so these are not called. *)

val client : (unit -> WebSharper_UI.Doc.t) -> WebSharper_UI.Doc.t
val hydrate : (unit -> WebSharper_UI.Doc.t) -> WebSharper_UI.Doc.t
val __client : string -> WebSharper_UI.Doc.t
val __hydrate : string -> (unit -> WebSharper_UI.Doc.t) -> WebSharper_UI.Doc.t
