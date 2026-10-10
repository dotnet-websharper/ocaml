(* Server (sitelet) API for wsocaml.

   This interface is shared: the frontend typechecks the user source against it
   (with the generated `WebSharper_UI` on the path), and the native server links
   the implementation (with the `WebSharper_UI` shadow). *)

type request = {
  method_ : string;
  path : string;
  query : (string * string) list;
  headers : (string * string) list;
  body : string;
}

type response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

type content = response

module Content : sig
  val text : string -> content
  val xml : string -> content
  val html : string -> content
  val page : ?title:string -> ?head:string -> WebSharper_UI.Doc.t list -> content
  val status : int -> content -> content
  val header : string -> string -> content -> content
end

type ('a) context = { link : 'a -> string; request : request }

module Sitelet : sig
  type ('a) t

  val make :
    (request -> 'a option) -> ('a -> string) -> (('a) context -> 'a -> content) -> ('a) t

  val empty : ('a) t
  val ( + ) : ('a) t -> ('a) t -> ('a) t

  (* Expanded by the frontend into `make` with a generated router/link. *)
  val infer : (('a) context -> 'a -> content) -> ('a) t
end

module Server : sig
  val serve : ?port:int -> ?static:string -> ?bundle:string -> ('a) Sitelet.t -> unit
end
