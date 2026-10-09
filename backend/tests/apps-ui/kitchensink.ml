open WebSharper_JavaScript
open WebSharper_UI
open WebSharper_UI.Html

(* Kitchen-sink: exercises OCaml/StdLib, WebSharper macros, HTML combinators,
   event handling and reactivity (Var/View) in a single program. Intended as
   the fast inner-loop check for incremental changes. *)
let () =
  (* OCaml stdlib + higher-order functions. *)
  let squares = List.map (fun x -> x * x) [ 1; 2; 3; 4 ] in
  let sum = List.fold_left ( + ) 0 squares in
  Console.log (Printf.sprintf "sum=%d len=%d" sum (List.length squares));

  (* WebSharper macro. *)
  let _hole = TemplateHole.makeText "a" "b" in

  (* Reactive HTML built with the combinators; attributes/children are lists. *)
  let count = Var.create 0 in
  let view =
    div
      [ Attr.create "id" "app" ]
      [ h1 [] [ Doc.text "Kitchen Sink" ];
        p
          [ On.click (fun _ _ -> Var.set count (Var.get count + 1)) ]
          [ Doc.text "count: "; Doc.textView (View.map (fun n -> Printf.sprintf "%d" n) (Var.view count)) ];
        ul [] (List.map (fun s -> li [] [ Doc.text s ]) [ "one"; "two"; "three" ]) ]
  in
  Doc.runById "root" view
