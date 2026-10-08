open Websharper_javascript

let () =
  Console.log_2 "hello from bindings";
  Console.log_2 (Printf.sprintf "sqrt=%.3f" (Math.sqrt 2.0));
  Console.log_2 (Printf.sprintf "json=%s" (JSON.stringify (JSON.parse "[1,2,3]")));
  Console.log_2 (Printf.sprintf "year=%d" (Date.getFullYear (Date.create_9 ())))
