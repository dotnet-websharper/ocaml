open WebSharper_UI
open WebSharper_UI.Html

(* HTML built with the WebSharper.UI combinators: `div`, `h1`, `b`, `ul`, `li`
   take attribute and child lists. *)
let () =
  let view =
    div []
      [ h1 [] [ Doc.text "Hello "; b [] [ Doc.text "WebSharper.UI" ] ];
        ul []
          [ li [] [ Doc.text "one" ];
            li [] [ Doc.text "two" ] ] ]
  in
  Doc.runById "root" view
