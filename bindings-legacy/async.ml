(* WebSharper.OCaml: minimal Async for [@rpc] call sites.

   On the client `Async.t` is backed by a JS promise (the runtime's `rpcCall`
   returns one), so `bind`/`map`/`run` chain it. The native server uses the
   matching implementation in runtimes/ocaml/async.ml. *)
type 'a t
external return : 'a -> 'a t = "js:Promise.resolve"
external bind : 'a t -> ('a -> 'b t) -> 'b t = "async_bind"
external map : ('a -> 'b) -> 'a t -> 'b t = "async_map"
external run : ('a -> unit) -> 'a t -> unit = "async_run"
external of_promise : Js.t -> 'a t = "%identity"
external to_promise : 'a t -> Js.t = "%identity"
