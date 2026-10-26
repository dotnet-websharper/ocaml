(* Typed JSON codec for the client bundle.

   `WebSharper_Json.encode v` / `WebSharper_Json.decode s` are *not* ordinary
   externals: the frontend rewrites each call into `__encode <n> v` /
   `__decode <n> s`, where `<n>` identifies the call site. After typechecking it
   reads the instantiated type off that node, describes it in the same external
   representation `[@rpc]`/`[@export]` use, and records the descriptor in the
   IR. The backend then lowers the primitive to
   `OCamlRuntime.jsonEncode(descriptor, v)` /
   `OCamlRuntime.jsonDecode(descriptor, s)`.

   The value-level types are the user-facing ones; the `__`-prefixed externals
   only exist so the rewritten call has something to typecheck against. There is
   no native implementation: these are client-only, and the native server never
   links this module (`let () =` bodies are dropped from `server.ml`). Keep this
   a `.ml` without an `.mli` — an interface drops the primitive from the `.cmi`,
   and the frontend then sees a plain global instead of a `ccall`. *)

external encode : 'a -> string = "wsocaml:json_encode_unindexed"

external decode : string -> 'a = "wsocaml:json_decode_unindexed"

external __encode : int -> 'a -> string = "wsocaml:json_encode"

external __decode : int -> string -> 'a = "wsocaml:json_decode"
