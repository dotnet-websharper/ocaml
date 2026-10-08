open Websharper_javascript

let () =
  let v = Wsui.create 0 in
  Wsui.set v 41;
  (* A Doc value built through the facade (rendering it, Wsui.run_by_id, works
     but starts WebSharper.UI's async scheduler, which needs further packaging
     support). *)
  let _doc = Wsui.append (Wsui.text "hello ") (Wsui.text "ui") in
  Console.log_2 (Printf.sprintf "v=%d" (Wsui.get v))
