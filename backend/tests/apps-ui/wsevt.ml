open WebSharper_JavaScript
open WebSharper_UI

(* Event handlers in attribute position use the reflected `Html.on` module,
   taking OCaml closures (mirroring F# `on.click (fun el ev -> ...)`). *)
let () =
  let a = On.click (fun el ev -> Console.log "clicked") in
  let _ = Attr.append a (Attr.empty ()) in
  Console.log (Printf.sprintf "built=%b" (a == a))
