(* Server-side rendering demo: a native OCaml server renders an HTML page (with
   an SSR `[@client]` region) and serves it; the client bundle hydrates it. *)

let page () =
  Ssr.render ~title:"SSR demo" ~scripts:[ "/Main.js" ]
    [
      Ssr.el "h1" [] [ Ssr.text "SSR Page" ];
      Ssr.el "p" [] [ Ssr.text "This paragraph is server-rendered." ];
      Ssr.client_region ~id:"app" "Main.app" [ Ssr.text "before" ];
    ]

let () =
  let handlers = Hashtbl.create 1 in
  Wsrpc.serve ~port:8123 ~page handlers
