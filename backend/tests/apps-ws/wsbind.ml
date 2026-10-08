open Websharper_javascript

let () =
  Console.log "hello from wsocaml";
  Console.warn "a warning";
  Console.error "now an error";
  let o = JSON.parse "{\"x\":1,\"y\":[2,3]}" in
  Console.log (JSON.stringify o)
