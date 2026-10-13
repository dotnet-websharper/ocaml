(* SSR driver for the generated Card_tpl module (native shadow). *)
let () =
  let c =
    Card_tpl.create ()
    |> Card_tpl.title "People"
    |> Card_tpl.link (WebSharper_UI.Attr.create "href" "/more")
    |> Card_tpl.body [ Ssr.el "b" [] [ Ssr.text "bold" ] ]
  in
  WebSharper_UI.Var.set c.vars.filter "abc";
  print_string (Ssr.render_nodes (Card_tpl.doc c))
