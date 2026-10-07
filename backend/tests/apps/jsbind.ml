let () =
  Console.log "hello from bindings";
  Console.log
    (Printf.sprintf "max=%.0f sqrt=%.3f pi=%.4f" (Math.max 3.0 8.0) (Math.sqrt 2.0) (Math.pi ()));
  let a = JsArray.create () in
  ignore (JsArray.push a (Js.to_js 10));
  ignore (JsArray.push a (Js.to_js 20));
  Console.log (Printf.sprintf "len=%d join=%s" (JsArray.length a) (JsArray.join a ","));
  Console.log (Printf.sprintf "json=%s" (Json.stringify (Json.parse "[1,2,3]")));
  Console.log (Printf.sprintf "year=%d" (JsDate.get_full_year (JsDate.create ())))
