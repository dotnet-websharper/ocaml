open Websharper_javascript

let () =
  Console.log "hello from bindings";
  Console.log (Printf.sprintf "sqrt=%.3f" (Math.sqrt 2.0));
  Console.log (Printf.sprintf "json=%s" (JSON.stringify (JSON.parse "[1,2,3]")));
  Console.log (Printf.sprintf "year=%d" (Date.getFullYear (Date.create_9 ())))
