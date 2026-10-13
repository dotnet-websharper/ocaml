(* A ppx that expands `[%template "path"]` into the generated template module.

   This exists so dune/merlin (ocaml-lsp) can expand templates for the editor:
   dune forwards `(preprocess (pps ...))` to merlin but not custom
   `(preprocess (action ...))`. The real build uses the frontend's own
   expansion (which also tracks the template as a dependency); this ppx shares
   the same `Codegen`. *)

open Ppxlib

let expand ~loc (path : string) : structure =
  let dir = Filename.dirname loc.loc_start.pos_fname in
  let full = if Filename.is_relative path then Filename.concat dir path else path in
  let src = In_channel.with_open_bin full In_channel.input_all in
  let base = Filename.remove_extension (Filename.basename full) |> String.lowercase_ascii in
  let code = Codegen.implementation ~base ~src (Hole.analyze (Markup.parse src)) in
  let lexbuf = Lexing.from_string code in
  Location.init lexbuf full;
  Parse.implementation lexbuf

let rule =
  Extension.declare "template" Extension.Context.module_expr
    Ast_pattern.(single_expr_payload (estring __))
    (fun ~loc ~path:_ path -> Ast_builder.Default.pmod_structure ~loc (expand ~loc path))

let () = Driver.register_transformation "wsocaml_template" ~rules:[ Context_free.Rule.extension rule ]
