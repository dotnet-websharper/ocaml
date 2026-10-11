(* Print the space-separated `requiredGlobals` of a `.wsir.json` file.
   Usage: required_globals <file.wsir.json>  (replaces an inline python one-liner) *)
let () =
  let json = Yojson.Safe.from_file Sys.argv.(1) in
  let gs =
    Yojson.Safe.Util.(json |> member "requiredGlobals" |> to_list |> List.map to_string)
  in
  print_string (String.concat " " gs)
