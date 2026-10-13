(* Generate an OCaml module (`.ml` + `.mli`) for a template file.

   Usage: template_gen <file.html> <out-dir> [<ModuleName>]
     <ModuleName> defaults to "<Basename>_tpl" (basename capitalized).
   The runtime `~base` is the lowercased basename (WS file id). *)

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  match args with
  | file :: out_dir :: rest ->
      let module_name =
        match rest with
        | name :: _ -> name
        | [] ->
            let b = Filename.remove_extension (Filename.basename file) in
            String.capitalize_ascii b ^ "_tpl"
      in
      let base =
        Filename.remove_extension (Filename.basename file) |> String.lowercase_ascii
      in
      let src = In_channel.with_open_bin file In_channel.input_all in
      let nodes = Html.parse src in
      let parsed = Hole.analyze nodes in
      let sig_text = Codegen.signature ~base parsed in
      let impl_text = Codegen.implementation ~base ~src parsed in
      let ocaml_path = Filename.concat out_dir module_name in
      let write path contents =
        let oc = open_out path in
        output_string oc contents;
        close_out oc
      in
      write (ocaml_path ^ ".mli") sig_text;
      write (ocaml_path ^ ".ml") impl_text;
      Printf.printf "wrote %s.ml/.mli (module %s, base %s, %d holes)\n" ocaml_path
        module_name base (List.length parsed.root.holes)
  | _ ->
      prerr_endline "usage: template_gen <file.html> <out-dir> [<ModuleName>]";
      exit 2
