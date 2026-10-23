(* Client code (a [@javascript] value) must not reference a server-only value. *)
open WebSharper_JavaScript

let secret = 42

let[@javascript] reveal () = Console.log (string_of_int secret)
