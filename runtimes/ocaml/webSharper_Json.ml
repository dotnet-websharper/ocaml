(* Native shadow of the client-only typed-JSON codec.

   `WebSharper_Json.encode`/`decode` are implemented by the client runtime
   (`backend/Runtime.js`: `jsonEncode`/`jsonDecode`), driven by a type descriptor
   the frontend reads off the call site. Application code normally uses them
   inside a `let () = …` block, which is dropped from `server.ml`, so the native
   server never runs this module. It exists so the same source also typechecks
   in a native/dune context (editor, `dune build`).

   There is no native implementation yet: a `yojson` interpreter of the same
   descriptor is a mechanical follow-on (see `JSON.md` §1.1). *)

let encode (_ : 'a) : string =
  failwith "WebSharper_Json.encode is client-only (JSON.md §1.1)"

let decode (_ : string) : 'a =
  failwith "WebSharper_Json.decode is client-only (JSON.md §1.1)"

let __encode (_ : int) (_ : 'a) : string =
  failwith "WebSharper_Json.encode is client-only (JSON.md §1.1)"

let __decode (_ : int) (_ : string) : 'a =
  failwith "WebSharper_Json.decode is client-only (JSON.md §1.1)"
