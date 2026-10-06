(*
 * websharper-ocaml: a strongly typed OCaml frontend for WebSharper.
 *
 * Copyright (c) 2026 IntelliFactory.
 * All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *)

open Asttypes
open Lambda

let jtag tag fields = `Assoc (("tag", `String tag) :: fields)

let norm_float s =
  if String.contains s 'p' || String.contains s 'P' || String.contains s 'x' || String.contains s 'X'
  then Printf.sprintf "%.17g" (float_of_string s)
  else s

(* [Ident.unique_name] is the semantic identity used to resolve references.
   [Ident.name] is the source-oriented spelling used only as a JS name hint. *)
let id_json id =
  `Assoc
    [
      ("id", `String (Ident.unique_name id)); ("name", `String (Ident.name id));
    ]

let const = function
  | Const_int x -> jtag "int" [ ("value", `String (string_of_int x)) ]
  | Const_float x -> jtag "float" [ ("value", `String (norm_float x)) ]
  | Const_char x -> jtag "char" [ ("value", `String (String.make 1 x)) ]
  | Const_string (x, _, _) -> jtag "string" [ ("value", `String x) ]
  | Const_int32 x -> jtag "int32" [ ("value", `String (Int32.to_string x)) ]
  | Const_int64 x -> jtag "int64" [ ("value", `String (Int64.to_string x)) ]
  | Const_nativeint x ->
      jtag "nativeint" [ ("value", `String (Nativeint.to_string x)) ]

let rec structured_const = function
  | Const_base c -> const c
  | Const_block (tag, xs) ->
      jtag "block"
        [
          ("blockTag", `Int tag); ("items", `List (List.map structured_const xs));
        ]
  | Const_float_array xs ->
      jtag "float_array" [ ("items", `List (List.map (fun x -> `String (norm_float x)) xs)) ]
  | Const_immstring s -> jtag "string" [ ("value", `String s) ]

let int_cmp = function
  | Ceq -> "eq"
  | Cne -> "ne"
  | Clt -> "lt"
  | Cgt -> "gt"
  | Cle -> "le"
  | Cge -> "ge"

let float_cmp = function
  | CFeq -> "eq"
  | CFneq -> "ne"
  | CFlt -> "lt"
  | CFnlt -> "nlt"
  | CFgt -> "gt"
  | CFngt -> "ngt"
  | CFle -> "le"
  | CFnle -> "nle"
  | CFge -> "ge"
  | CFnge -> "nge"

let array_kind = function
  | Pgenarray -> "generic"
  | Paddrarray -> "addr"
  | Pintarray -> "int"
  | Pfloatarray -> "float"

let ctconst_value = function
  | Big_endian -> 0
  | Word_size -> 64
  | Int_size -> 63
  | Max_wosize -> 4611686018427387903
  | Ostype_unix -> 1
  | Ostype_win32 -> 0
  | Ostype_cygwin -> 0
  | Backend_type -> 0

let boxed_kind = function
  | Pnativeint -> "nativeint"
  | Pint32 -> "int32"
  | Pint64 -> "int64"

let safe = function Safe -> true | Unsafe -> false

let primitive p =
  let simple s = jtag s [] in
  match p with
  | Pbytes_to_string -> simple "bytes_to_string"
  | Pbytes_of_string -> simple "bytes_of_string"
  | Pignore -> simple "ignore"
  | Pgetglobal id -> jtag "getglobal" [ ("name", `String (Ident.name id)) ]
  | Psetglobal id -> jtag "setglobal" [ ("name", `String (Ident.name id)) ]
  | Pmakeblock (tag, mut, _) ->
      jtag "makeblock"
        [ ("blockTag", `Int tag); ("mutable", `Bool (mut = Mutable)) ]
  | Pfield (i, _, _) -> jtag "field" [ ("index", `Int i) ]
  | Pfield_computed -> simple "field_computed"
  | Psetfield (i, _, _) -> jtag "setfield" [ ("index", `Int i) ]
  | Psetfield_computed _ -> simple "setfield_computed"
  | Pmakelazyblock Lazy_tag -> simple "makelazy"
  | Pmakelazyblock Forward_tag -> simple "makeforward"
  | Patomic_load -> simple "atomic_load"
  | Pfloatfield i -> jtag "field" [ ("index", `Int i) ]
  | Psetfloatfield (i, _) -> jtag "setfield" [ ("index", `Int i) ]
  | Psequand -> simple "and"
  | Psequor -> simple "or"
  | Pnot -> simple "not"
  | Pnegint -> simple "negint"
  | Paddint -> simple "addint"
  | Psubint -> simple "subint"
  | Pmulint -> simple "mulint"
  | Pdivint s -> jtag "divint" [ ("safe", `Bool (safe s)) ]
  | Pmodint s -> jtag "modint" [ ("safe", `Bool (safe s)) ]
  | Pandint -> simple "bitand"
  | Porint -> simple "bitor"
  | Pxorint -> simple "bitxor"
  | Plslint -> simple "lsl"
  | Plsrint -> simple "lsr"
  | Pasrint -> simple "asr"
  | Pintcomp c -> jtag "intcomp" [ ("op", `String (int_cmp c)) ]
  | Pcompare_ints -> simple "intcompare"
  | Pcompare_floats -> simple "compare_floats"
  | Pduparray (k, _) -> jtag "dup_array" [ ("kind", `String (array_kind k)) ]
  | Poffsetint n -> jtag "offsetint" [ ("value", `Int n) ]
  | Poffsetref n -> jtag "offsetref" [ ("value", `Int n) ]
  | Pintoffloat -> simple "intoffloat"
  | Pfloatofint -> simple "floatofint"
  | Pnegfloat -> simple "negfloat"
  | Pabsfloat -> simple "absfloat"
  | Paddfloat -> simple "addfloat"
  | Psubfloat -> simple "subfloat"
  | Pmulfloat -> simple "mulfloat"
  | Pdivfloat -> simple "divfloat"
  | Pfloatcomp c -> jtag "floatcomp" [ ("op", `String (float_cmp c)) ]
  | Pstringlength -> simple "stringlength"
  | Pstringrefu -> simple "stringref"
  | Pstringrefs -> simple "stringref"
  | Pbyteslength -> simple "byteslength"
  | Pbytesrefu -> simple "bytesref"
  | Pbytesrefs -> simple "bytesref"
  | Pbytessetu -> simple "bytesset"
  | Pbytessets -> simple "bytesset"
  | Pmakearray (k, m) ->
      jtag "makearray"
        [ ("kind", `String (array_kind k)); ("mutable", `Bool (m = Mutable)) ]
  | Parraylength k -> jtag "arraylength" [ ("kind", `String (array_kind k)) ]
  | Parrayrefu k | Parrayrefs k ->
      jtag "arrayref" [ ("kind", `String (array_kind k)) ]
  | Parraysetu k | Parraysets k ->
      jtag "arrayset" [ ("kind", `String (array_kind k)) ]
  | Pisint -> simple "isint"
  | Pisout -> simple "isout"
  | Pbintofint k -> jtag "bintofint" [ ("kind", `String (boxed_kind k)) ]
  | Pintofbint k -> jtag "intofbint" [ ("kind", `String (boxed_kind k)) ]
  | Pnegbint k -> jtag "negbint" [ ("kind", `String (boxed_kind k)) ]
  | Paddbint k -> jtag "addbint" [ ("kind", `String (boxed_kind k)) ]
  | Psubbint k -> jtag "subbint" [ ("kind", `String (boxed_kind k)) ]
  | Pmulbint k -> jtag "mulbint" [ ("kind", `String (boxed_kind k)) ]
  | Pandbint k -> jtag "andbint" [ ("kind", `String (boxed_kind k)) ]
  | Porbint k -> jtag "orbint" [ ("kind", `String (boxed_kind k)) ]
  | Pxorbint k -> jtag "xorbint" [ ("kind", `String (boxed_kind k)) ]
  | Plslbint k -> jtag "lslbint" [ ("kind", `String (boxed_kind k)) ]
  | Plsrbint k -> jtag "lsrbint" [ ("kind", `String (boxed_kind k)) ]
  | Pasrbint k -> jtag "asrbint" [ ("kind", `String (boxed_kind k)) ]
  | Pdivbint { size; _ } -> jtag "divbint" [ ("kind", `String (boxed_kind size)) ]
  | Pmodbint { size; _ } -> jtag "modbint" [ ("kind", `String (boxed_kind size)) ]
  | Pcompare_bints k -> jtag "compare_bints" [ ("kind", `String (boxed_kind k)) ]
  | Pcvtbint (s, d) ->
      jtag "cvtbint"
        [ ("src", `String (boxed_kind s)); ("kind", `String (boxed_kind d)) ]
  | Pbbswap k -> jtag "bbswap" [ ("kind", `String (boxed_kind k)) ]
  | Pbytes_set_16 s -> jtag "bytes_set16" [ ("safe", `Bool s) ]
  | Pbytes_set_32 s -> jtag "bytes_set32" [ ("safe", `Bool s) ]
  | Pbytes_set_64 s -> jtag "bytes_set64" [ ("safe", `Bool s) ]
  | Pbytes_load_16 s -> jtag "bytes_get16" [ ("safe", `Bool s) ]
  | Pbytes_load_32 s -> jtag "bytes_get32" [ ("safe", `Bool s) ]
  | Pbytes_load_64 s -> jtag "bytes_get64" [ ("safe", `Bool s) ]
  | Pctconst c -> jtag "ctconst" [ ("value", `Int (ctconst_value c)) ]
  | Pbswap16 -> simple "bswap16"
  | Pbintcomp (k, c) ->
      jtag "bintcomp"
        [ ("kind", `String (boxed_kind k)); ("op", `String (int_cmp c)) ]
  | Praise _ -> simple "raise"
  | Pccall d -> jtag "ccall" [ ("name", `String d.prim_name) ]
  | Popaque -> simple "opaque"
  | Ppoll -> simple "poll"
  | p -> failwith ("unsupported Lambda primitive: " ^ Printlambda.name_of_primitive p)

let rec lambda = function
  | Lvar id -> jtag "var" [ ("var", id_json id) ]
  | Lmutvar id -> jtag "var" [ ("var", id_json id) ]
  | Lconst c -> jtag "const" [ ("value", structured_const c) ]
  | Lapply a ->
      jtag "apply"
        [
          ("func", lambda a.ap_func); ("args", `List (List.map lambda a.ap_args));
        ]
  | Lfunction f ->
      jtag "fun"
        [
          ("params", `List (List.map (fun (id, _) -> id_json id) f.params));
          ("body", lambda f.body);
        ]
  | Llet (_, _, id, v, b) | Lmutlet (_, id, v, b) ->
      jtag "let"
        [ ("var", id_json id); ("value", lambda v); ("body", lambda b) ]
  | Lletrec (bs, b) ->
      jtag "letrec"
        [
          ( "bindings",
            `List
              (List.map
                 (fun r ->
                   `Assoc
                     [
                       ("var", id_json r.id); ("value", lambda (Lfunction r.def));
                     ])
                 bs) );
          ("body", lambda b);
        ]
  | Lprim (p, args, _) ->
      jtag "prim"
        [ ("prim", primitive p); ("args", `List (List.map lambda args)) ]
  | Lswitch (x, s, _) ->
      jtag "switch"
        [
          ("expr", lambda x);
          ( "consts",
            `List
              (List.map
                 (fun (k, v) -> `Assoc [ ("key", `Int k); ("body", lambda v) ])
                 s.sw_consts) );
          ( "blocks",
            `List
              (List.map
                 (fun (k, v) -> `Assoc [ ("key", `Int k); ("body", lambda v) ])
                 s.sw_blocks) );
          ( "fail",
            match s.sw_failaction with None -> `Null | Some x -> lambda x );
        ]
  | Lstringswitch (x, cs, d, _) ->
      jtag "stringswitch"
        [
          ("expr", lambda x);
          ( "cases",
            `List
              (List.map
                 (fun (k, v) ->
                   `Assoc [ ("key", `String k); ("body", lambda v) ])
                 cs) );
          ("fail", match d with None -> `Null | Some x -> lambda x);
        ]
  | Lstaticraise (n, xs) ->
      jtag "staticraise"
        [ ("id", `Int n); ("args", `List (List.map lambda xs)) ]
  | Lstaticcatch (b, (n, ids), h) ->
      jtag "staticcatch"
        [
          ("body", lambda b);
          ("id", `Int n);
          ("params", `List (List.map (fun (id, _) -> id_json id) ids));
          ("handler", lambda h);
        ]
  | Ltrywith (b, id, h) ->
      jtag "trywith"
        [ ("body", lambda b); ("var", id_json id); ("handler", lambda h) ]
  | Lifthenelse (a, b, c) ->
      jtag "if" [ ("cond", lambda a); ("then", lambda b); ("else", lambda c) ]
  | Lsequence (a, b) -> jtag "seq" [ ("first", lambda a); ("second", lambda b) ]
  | Lwhile (a, b) -> jtag "while" [ ("cond", lambda a); ("body", lambda b) ]
  | Lfor (id, a, b, dir, body) ->
      jtag "for"
        [
          ("var", id_json id);
          ("from", lambda a);
          ("to", lambda b);
          ("down", `Bool (dir = Downto));
          ("body", lambda body);
        ]
  | Lassign (id, v) ->
      jtag "assign" [ ("var", id_json id); ("value", lambda v) ]
  | Levent (x, _) -> lambda x
  | Lifused (_, x) -> lambda x
  | Lsend _ -> failwith "objects/method sends are not supported yet"

let parse file =
  let ch = open_in_bin file in
  Fun.protect ~finally:(fun () -> close_in ch) @@ fun () ->
  let lb = Lexing.from_channel ch in
  Location.init lb file;
  Parse.implementation lb

let () =
  let input = ref ""
  and output = ref ""
  and unit_name = ref ""
  and includes = ref [] in
  Arg.parse
    [
      ("--input", Arg.Set_string input, ".ml input");
      ("--output", Arg.Set_string output, "IR output");
      ("--unit", Arg.Set_string unit_name, "unit name");
      ("-I", Arg.String (fun x -> includes := x :: !includes), "include dir");
    ]
    (fun _ -> ())
    "wsocaml-frontend";
  if !input = "" then (
    prerr_endline "--input required";
    exit 2);
  try
    Clflags.include_dirs := List.rev !includes @ !Clflags.include_dirs;
    Compmisc.init_path ();
    let env = Compmisc.initial_env () in
    let ast = parse !input in
    let typed, _, _, _, _ = Typemod.type_structure env ast in
    let u =
      if !unit_name <> "" then !unit_name
      else
        String.capitalize_ascii
          (Filename.remove_extension (Filename.basename !input))
    in
    let program = Translmod.transl_implementation u (typed, Tcoerce_none) in
    let json =
      `Assoc
        [
          ("schema", `String "wsocaml-ir-4");
          ("unit", `String u);
          ("moduleIdent", `String (Ident.name program.module_ident));
          ("mainModuleBlockSize", `Int program.main_module_block_size);
          ( "requiredGlobals",
            `List
              (Ident.Set.elements program.required_globals
              |> List.map (fun x -> `String (Ident.name x))) );
          ("code", lambda program.code);
        ]
    in
    if !output = "" then Yojson.Safe.pretty_to_channel stdout json
    else Yojson.Safe.to_file !output json
  with exn ->
    Location.report_exception Format.err_formatter exn;
    prerr_endline (Printexc.to_string exn);
    exit 1
