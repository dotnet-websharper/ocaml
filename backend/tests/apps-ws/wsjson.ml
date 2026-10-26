open WebSharper_JavaScript

(* `open WebSharper_JavaScript` shadows the OCaml `String`; keep it. *)
module String = Stdlib.String

(* Typed JSON (`WebSharper_Json.encode`/`decode`): the value's OCaml type is
   described in the same external representation `[@rpc]`/`[@export]` use —
   records as objects, variants as `{"$":…}`, lists/arrays as arrays, options as
   value/`null`, tuples as arrays. No DOM needed, so the driver is plain node. *)

type todo = { id : int; title : string; completed : bool }
type shape = Dot | Circle of int | Rect of int * int

type payload =
  { todos : todo list;
    shapes : shape array;
    note : string option;
    pair : string * int;
    nested : int list option }

let () =
  let p =
    { todos =
        [ { id = 1; title = "a \"b\"\n\tc\\d"; completed = true };
          { id = -2; title = "ü"; completed = false } ];
      shapes = [| Dot; Circle 5; Rect (2, 3) |];
      note = Some "hi";
      pair = ("k", 7);
      nested = None }
  in
  let s = WebSharper_Json.encode p in
  Console.log ("encode=" ^ s);
  let q : payload = WebSharper_Json.decode s in
  Console.log ("roundtrip=" ^ string_of_bool (WebSharper_Json.encode q = s));
  (* A hand-written payload in the same representation decodes type-safely. *)
  let lit =
    "{\"todos\":[],\"shapes\":[{\"$\":\"Circle\",\"$0\":9}],\"note\":null,"
    ^ "\"pair\":[\"x\",1],\"nested\":[4,5]}"
  in
  let r : payload = WebSharper_Json.decode lit in
  let show_pair (pr : string * int) =
    let a, b = pr in
    a ^ ":" ^ string_of_int b
  in
  Console.log ("decode=" ^ string_of_bool (r.note = None) ^ "," ^ show_pair r.pair);
  Console.log ("reencode=" ^ WebSharper_Json.encode r);
  let ints : int list = WebSharper_Json.decode "[1,2,3]" in
  Console.log ("ints=" ^ String.concat "," (List.map string_of_int ints));
  let flag : bool = WebSharper_Json.decode "true" in
  Console.log ("bool=" ^ string_of_bool flag)
