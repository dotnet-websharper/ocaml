let () =
  Console.log_2 "hello from wsocaml";
  Console.warn_2 "a warning";
  Console.error_2 "now an error";
  let o = JSON.parse "{\"x\":1,\"y\":[2,3]}" in
  Console.log_2 (JSON.stringify o)
