(* Normalize wsocaml build diagnostics to a single line
   `file:line:startCol:endCol: severity: message` for the VS Code problem matcher.

   The OCaml frontend and ocamlc/ocamlopt emit the multi-line report

     File "<path>", lines <L>[-<L2>], characters <A>[-<B>]:
     <source line>            (ocamlc only)
     <caret>                  (ocamlc only)
     Error: <message...>
     <continuation lines...>
     Hint: ...
     Typecore.Error(_, _, _)   (frontend only)

   which a problem matcher cannot consume directly. Columns are 1-based in the
   output. All other lines pass through unchanged.

   Usage: <tool output> | diag *)

let is_prefix p s =
  String.length s >= String.length p && String.sub s 0 (String.length p) = p

let starts_with_space s = String.length s > 0 && (s.[0] = ' ' || s.[0] = '\t')
let is_digit c = c >= '0' && c <= '9'

(* `^[A-Z][A-Za-z0-9_]*\.[A-Za-z_]+(...)$` — the redundant `Printexc.to_string
   exn` line the frontend prints *after* a formatted report (e.g.
   `Typecore.Error(_, _, _)`).

   It must not match an exception *message*: those end up in the terminal as
   `System.Exception: …` / `Unhandled exception. …` / `Fatal error: exception …`
   (all contain a colon), and dropping one hides the only useful line when the
   failure has no `File "…", lines …` location. *)
let is_exception s =
  let n = String.length s in
  n > 0 && s.[0] >= 'A' && s.[0] <= 'Z' && String.contains s '.' && s.[n - 1] = ')'
  && not (String.contains s ':')

let skip_to_digit s i =
  let j = ref i in
  while !j < String.length s && not (is_digit s.[!j]) do
    incr j
  done;
  !j

(* [i] points at a digit; return the value and the index just after the digits. *)
let read_int s i =
  let j = ref i in
  while !j < String.length s && is_digit s.[!j] do
    incr j
  done;
  if !j = i then None else Some (int_of_string (String.sub s i (!j - i)), !j)

(* Parse `File "…", lines A[-B], characters C[-D]:` -> (path, line, col, endcol). *)
let parse_header s =
  if not (is_prefix "File \"" s) then None
  else
    match String.index_from_opt s 6 '"' with
    | None -> None
    | Some q ->
        let path = String.sub s 6 (q - 6) in
        let rest = String.sub s (q + 1) (String.length s - q - 1) in
        (* Optional `-L2` (end line) is skipped. *)
        let after_line i = if i < String.length rest && rest.[i] = '-' then (match read_int rest (i + 1) with Some (_, j) -> j | None -> i) else i in
        (match read_int rest (skip_to_digit rest 0) with
         | None -> None
         | Some (line, i1) ->
             (match read_int rest (skip_to_digit rest (after_line i1)) with
              | None -> None
              | Some (col, i2) ->
                  let endcol = if i2 < String.length rest && rest.[i2] = '-' then (match read_int rest (i2 + 1) with Some (e, _) -> Some e | None -> None) else None in
                  Some (path, line, col, endcol)))

(* `Error: msg` / `Warning: msg` / `Warning NN [name]: msg` -> (severity, message). *)
let message_of s =
  if is_prefix "Error:" s then Some ("error", String.trim (String.sub s 6 (String.length s - 6)))
  else if is_prefix "Warning:" s then Some ("warning", String.trim (String.sub s 8 (String.length s - 8)))
  else if is_prefix "Warning " s then
    match String.index_opt s ':' with
    | Some i -> Some ("warning", String.trim (String.sub s (i + 1) (String.length s - i - 1)))
    | None -> None
  else None

let () =
  let out = Buffer.create 1024 in
  let path = ref None
  and line = ref 0
  and col = ref 0
  and endcol = ref None
  and message = ref None in
  let flush () =
    (match (!path, !message) with
     | Some p, Some (sev, msg) ->
         let start = !col + 1 in
         let stop = match !endcol with Some e -> e + 1 | None -> start + 1 in
         Buffer.add_string out (Printf.sprintf "%s:%d:%d:%d: %s: %s\n" p !line start stop sev msg)
     | _ -> ());
    path := None;
    message := None
  in
  let handle s =
    match parse_header s with
    | Some (p, l, c, e) ->
        flush ();
        path := Some p;
        line := l;
        col := c;
        endcol := e
    | None ->
        if !path = None then (
          if not (is_exception s) then Buffer.add_string out (s ^ "\n"))
        else
          match !message with
          | None -> (match message_of s with Some m -> message := Some m | None -> ())
          | Some (sev, msg) ->
              if (starts_with_space s || is_prefix "Hint:" s) && not (is_exception (String.trim s)) then
                message := Some (sev, msg ^ " " ^ String.trim s)
              else (
                flush ();
                if not (is_exception s) then Buffer.add_string out (s ^ "\n"))
  in
  (try
     while true do
       handle (input_line stdin)
     done
   with End_of_file -> ());
  flush ();
  print_string (Buffer.contents out)
