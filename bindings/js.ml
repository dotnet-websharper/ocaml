type t
external to_js : 'a -> t = "%identity"
external of_js : t -> 'a = "%identity"
external get : t -> string -> t = "jsdget"
external set : t -> string -> t -> unit = "jsdset"
external get_index : t -> int -> t = "jsdget"
external set_index : t -> int -> t -> unit = "jsdset"
