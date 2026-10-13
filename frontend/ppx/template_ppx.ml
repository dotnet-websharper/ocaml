(* A ppx that expands `[%template "path"]` into the generated template module.

   This exists so dune/merlin (ocaml-lsp) can expand templates for the editor:
   dune forwards `(preprocess (pps ...))` to merlin but not custom
   `(preprocess (action ...))`. The real build uses the frontend's own
   expansion (which also tracks the template as a dependency); this ppx shares
   the same `Codegen`. *)

open Ppxlib

(* Dune runs the ppx from `_build/<context>/...`, where the template file is not
   copied (ppx dependencies are not tracked). Map the input file's directory back
   to the source tree by dropping a `_build/<context>/` segment. *)
let source_dir (path : string) : string =
  let abs = if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path in
  let dir = Filename.dirname abs in
  let marker = "/_build/" in
  let mlen = String.length marker in
  let rec find i =
    if i + mlen > String.length dir then None
    else if String.sub dir i mlen = marker then Some i
    else find (i + 1)
  in
  match find 0 with
  | None -> dir
  | Some i ->
      let j =
        match String.index_from_opt dir (i + mlen) '/' with
        | Some j -> j
        | None -> String.length dir
      in
      String.sub dir 0 i ^ String.sub dir j (String.length dir - j)

let expand ~path (template : string) : structure =
  let dir = source_dir path in
  let full =
    if Filename.is_relative template then Filename.concat dir template else template
  in
  let src = In_channel.with_open_bin full In_channel.input_all in
  let base = Filename.remove_extension (Filename.basename full) |> String.lowercase_ascii in
  let code = Codegen.implementation ~base ~src (Hole.analyze (Markup.parse src)) in
  let lexbuf = Lexing.from_string code in
  Location.init lexbuf full;
  Parse.implementation lexbuf

let rule =
  Extension.declare "template" Extension.Context.module_expr
    Ast_pattern.(single_expr_payload (estring __))
    (fun ~loc ~path template -> Ast_builder.Default.pmod_structure ~loc (expand ~path template))

let () = Driver.register_transformation "wsocaml_template" ~rules:[ Context_free.Rule.extension rule ]
