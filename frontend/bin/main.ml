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
  | Pccall d ->
      let name =
        match String.index_opt d.prim_name ' ' with
        | Some i -> String.sub d.prim_name 0 i
        | None -> d.prim_name
      in
      jtag "ccall" [ ("name", `String name) ]
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

(* Client/server boundary.
   [@javascript] marks a JS-targeted (client) value; [@rpc] marks a server
   value callable from the client; every other top-level value is server-only
   and must not be referenced by client-side code. *)
let attrNames (attrs: Parsetree.attributes) =
  List.map (fun (a: Parsetree.attribute) -> a.attr_name.txt) attrs

let clientMarks (ast: Parsetree.structure) =
  let js = ref [] and rpc = ref [] and srv = ref [] in
  List.iter
    (fun (item: Parsetree.structure_item) ->
      match item.pstr_desc with
      | Parsetree.Pstr_value (_, vbs) ->
          List.iter
            (fun (vb: Parsetree.value_binding) ->
              match vb.pvb_pat.ppat_desc with
              | Parsetree.Ppat_var { txt = n; _ } ->
                  let a = attrNames vb.pvb_attributes in
                  if List.mem "javascript" a || List.mem "export" a || List.mem "client" a then js := n :: !js
                  else if List.mem "rpc" a then rpc := n :: !rpc
                  else srv := n :: !srv
              | _ -> ())
            vbs
      | _ -> ())
    ast;
  (List.rev !js, List.rev !rpc, List.rev !srv)

(* Names of top-level values marked [@client] (server-rendered regions the client
   hydrates). *)
let clientNames (ast: Parsetree.structure) =
  let acc = ref [] in
  List.iter
    (fun (item: Parsetree.structure_item) ->
      match item.pstr_desc with
      | Parsetree.Pstr_value (_, vbs) ->
          List.iter
            (fun (vb: Parsetree.value_binding) ->
              match vb.pvb_pat.ppat_desc with
              | Parsetree.Ppat_var { txt = n; _ } ->
                  if List.mem "client" (attrNames vb.pvb_attributes) then acc := n :: !acc
              | _ -> ())
            vbs
      | _ -> ())
    ast;
  List.rev !acc

(* Name of the top-level [@website] value (the served sitelet). *)
let websiteMarks (ast: Parsetree.structure) =
  let acc = ref [] in
  List.iter
    (fun (item: Parsetree.structure_item) ->
      match item.pstr_desc with
      | Parsetree.Pstr_value (_, vbs) ->
          List.iter
            (fun (vb: Parsetree.value_binding) ->
              match vb.pvb_pat.ppat_desc with
              | Parsetree.Ppat_var { txt = n; _ } ->
                  if List.mem "website" (attrNames vb.pvb_attributes) then acc := n :: !acc
              | _ -> ())
            vbs
      | _ -> ())
    ast;
  List.rev !acc

(* Names of top-level values marked [@export] (part of the JS API). *)
let exportMarks (ast: Parsetree.structure) =
  let acc = ref [] in
  List.iter
    (fun (item: Parsetree.structure_item) ->
      match item.pstr_desc with
      | Parsetree.Pstr_value (_, vbs) ->
          List.iter
            (fun (vb: Parsetree.value_binding) ->
              match vb.pvb_pat.ppat_desc with
              | Parsetree.Ppat_var { txt = n; _ } ->
                  if List.mem "export" (attrNames vb.pvb_attributes) then acc := n :: !acc
              | _ -> ())
            vbs
      | _ -> ())
    ast;
  List.rev !acc

let referencedNames (e: Parsetree.expression) =
  let acc = ref [] in
  let it =
    {
      Ast_iterator.default_iterator with
      expr =
        (fun self (e: Parsetree.expression) ->
          (match e.pexp_desc with
          | Parsetree.Pexp_ident { txt = Longident.Lident n; _ } -> acc := n :: !acc
          | _ -> ());
          Ast_iterator.default_iterator.expr self e);
    }
  in
  it.expr it e;
  !acc

let checkBoundary (ast: Parsetree.structure) =
  let role = Hashtbl.create 16 in
  List.iter
    (fun (item: Parsetree.structure_item) ->
      match item.pstr_desc with
      | Parsetree.Pstr_value (_, vbs) ->
          List.iter
            (fun (vb: Parsetree.value_binding) ->
              match vb.pvb_pat.ppat_desc with
              | Parsetree.Ppat_var { txt = n; _ } ->
                  let a = attrNames vb.pvb_attributes in
                  let r =
                    if List.mem "javascript" a || List.mem "export" a || List.mem "client" a then "js"
                    else if List.mem "rpc" a then "rpc"
                    else "server"
                  in
                  Hashtbl.replace role n r
              | _ -> ())
            vbs
      | _ -> ())
    ast;
  List.iter
    (fun (item: Parsetree.structure_item) ->
      match item.pstr_desc with
      | Parsetree.Pstr_value (_, vbs) ->
          List.iter
            (fun (vb: Parsetree.value_binding) ->
              match vb.pvb_pat.ppat_desc with
              | Parsetree.Ppat_var { txt = n; _ } when (try Hashtbl.find role n = "js" with Not_found -> false) ->
                  referencedNames vb.pvb_expr
                  |> List.iter (fun r ->
                         match (try Some (Hashtbl.find role r) with Not_found -> None) with
                         | Some "server" ->
                             failwith (
                               Printf.sprintf
                                 "client-side '%s' references server-only '%s'; mark it [@javascript] or [@rpc]"
                                 n r)
                         | _ -> ())
              | _ -> ())
            vbs
      | _ -> ())
    ast

(* --- Native server generation ---
   Emit an OCaml program that re-runs the server-only + [@rpc] definitions and
   serves them over JSON-RPC, with type-directed codecs for supported types. *)

(* [@rpc]/[@export] codecs. Values cross the boundary in a JS-idiomatic
   representation: records -> objects keyed by field name, variants ->
   {"$":"Case","$0":...,"$1":...}, lists/arrays -> JSON arrays, options ->
   null/value, tuples -> arrays; ints/floats/bools/strings are JSON scalars and
   chars are 1-char strings. The internal OCaml runtime representation is
   unchanged. Codecs are generated from the inferred types; recursive
   record/variant types get named helper codecs, specialized per concrete
   instantiation. *)

let rec subst (sub: (string * Types.type_expr) list) (t: Types.type_expr) : Types.type_expr =
  match Types.get_desc t with
  | Types.Tvar (Some n) when List.mem_assoc n sub -> List.assoc n sub
  | Types.Tconstr (p, args, _) ->
      Btype.newgenty (Types.Tconstr (p, List.map (subst sub) args, ref Types.Mnil))
  | Types.Ttuple ts -> Btype.newgenty (Types.Ttuple (List.map (fun (l, ty) -> (l, subst sub ty)) ts))
  | Types.Tarrow (l, a, b, c) -> Btype.newgenty (Types.Tarrow (l, subst sub a, subst sub b, c))
  | _ -> t

let paramsOf (d: Types.type_declaration) =
  List.filter_map
    (fun t -> match Types.get_desc t with Types.Tvar (Some n) -> Some n | _ -> None)
    d.type_params

let withSub (d: Types.type_declaration) (args: Types.type_expr list) =
  let names = paramsOf d in
  List.combine names (List.filteri (fun i _ -> i < List.length names) args)

let ctorArgs (c: Types.constructor_declaration) =
  match c.cd_args with
  | Types.Cstr_tuple ts -> Some ts
  | Types.Cstr_record _ -> None

let isConstCtor (c: Types.constructor_declaration) = ctorArgs c = Some []

let indexOf x xs =
  let rec go i = function
    | [] -> failwith "indexOf"
    | y :: ys -> if y == x then i else go (i + 1) ys
  in
  go 0 xs

let builtinPath (p: Path.t) =
  List.exists (fun q -> Path.same p q)
    [ Predef.path_int; Predef.path_string; Predef.path_bool; Predef.path_float;
      Predef.path_char; Predef.path_unit; Predef.path_list; Predef.path_option;
      Predef.path_array ]

let unsupportedBoxed (p: Path.t) =
  List.exists (fun q -> Path.same p q)
    [ Predef.path_int32; Predef.path_int64; Predef.path_nativeint ]

(* A type path flattened to a valid OCaml identifier fragment. *)
let typeName (p: Path.t) =
  let s = Path.name p in
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      let ok =
        (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'
      in
      Buffer.add_char b (if ok then c else '_'))
    s;
  Buffer.contents b

(* A key for a concrete instantiation, e.g. `int tree` -> "tree_int". *)
let rec instKey (t: Types.type_expr) : string =
  match Types.get_desc t with
  | Types.Tconstr (p, [], _) -> typeName p
  | Types.Tconstr (p, args, _) -> typeName p ^ "_" ^ String.concat "_" (List.map instKey args)
  | Types.Ttuple ts -> "tup_" ^ String.concat "_" (List.map (fun (_, x) -> instKey x) ts)
  | Types.Tvar (Some n) -> failwith ("unresolved type variable '" ^ n ^ "' in [@rpc] signature")
  | Types.Tvar None -> failwith "unresolved type variable in [@rpc] signature"
  | _ -> failwith "unresolved type in [@rpc] signature"

let obj (fields: (string * string) list) =
  "`Assoc [" ^ String.concat "; " (List.map (fun (k, v) -> Printf.sprintf "(%S, %s)" k v) fields) ^ "]"

let rec enc env recSet seen (t: Types.type_expr) : string =
  match Types.get_desc t with
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_int -> "(fun x -> `Int x)"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_bool -> "(fun x -> `Bool x)"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_string -> "(fun x -> `String x)"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_float -> "(fun x -> `Float x)"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_char -> "(fun x -> `String (String.make 1 x))"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_unit -> "(fun () -> `Null)"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_list ->
      "(fun xs -> `List (List.map (" ^ enc env recSet seen a ^ ") xs))"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_option ->
      "(fun v -> match v with None -> `Null | Some x -> (" ^ enc env recSet seen a ^ ") x)"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_array ->
      "(fun xs -> `List (Array.to_list (Array.map (" ^ enc env recSet seen a ^ ") xs)))"
  | Types.Tconstr (p, args, _) ->
      let k = instKey t in
      if List.mem k recSet then "toJson_" ^ k else encNamed env recSet seen k (Env.find_type p env) args
  | Types.Ttuple ts ->
      let ts = List.map snd ts in
      let vars = List.mapi (fun i _ -> Printf.sprintf "a%d" i) ts in
      let items = List.map2 (fun v t -> "(" ^ enc env recSet seen t ^ ") " ^ v) vars ts in
      "(fun (" ^ String.concat ", " vars ^ ") -> `List [" ^ String.concat "; " items ^ "])"
  | _ -> failwith "unsupported [@rpc] type (encoder)"

and encNamed env recSet seen key (d: Types.type_declaration) args =
  if List.mem key seen then failwith ("recursive [@rpc] type: " ^ key);
  let sub = withSub d args in
  match d.type_kind with
  | Types.Type_abstract _ ->
      (match d.type_manifest with
       | Some m -> enc env recSet seen (subst sub m)
       | None -> failwith ("unsupported abstract [@rpc] type: " ^ key))
  | Types.Type_record (labels, _) ->
      let fields =
        List.map
          (fun (l: Types.label_declaration) ->
            let fn = Ident.name l.ld_id in
            (fn, "(" ^ enc env recSet (key :: seen) (subst sub l.ld_type) ^ ") x." ^ fn))
          labels
      in
      "(fun x -> " ^ obj fields ^ ")"
  | Types.Type_variant (ctors, _) ->
      let cases =
        ctors
        |> List.map (fun (c: Types.constructor_declaration) ->
               let cname = Ident.name c.cd_id in
               if isConstCtor c then
                 Printf.sprintf "%s -> %s" cname (obj [ ("$", Printf.sprintf "`String %S" cname) ])
               else
                 let ts = List.map (subst sub) (Option.get (ctorArgs c)) in
                 let vars = List.mapi (fun i _ -> Printf.sprintf "v%d" i) ts in
                 let fields =
                   ("$", Printf.sprintf "`String %S" cname)
                   :: List.mapi
                        (fun i t ->
                          ( "$" ^ string_of_int i,
                            "(" ^ enc env recSet (key :: seen) t ^ ") v" ^ string_of_int i ))
                        ts
                 in
                 let pat = match vars with [ v ] -> v | vs -> "(" ^ String.concat ", " vs ^ ")" in
                 Printf.sprintf "%s %s -> %s" cname pat (obj fields))
      in
      "(fun x -> match x with " ^ String.concat " | " cases ^ ")"
  | _ -> failwith ("unsupported [@rpc] type: " ^ key)

let rec dec env recSet seen (t: Types.type_expr) : string =
  match Types.get_desc t with
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_int -> "Yojson.Safe.Util.to_int"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_bool -> "Yojson.Safe.Util.to_bool"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_float -> "Yojson.Safe.Util.to_float"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_string -> "Yojson.Safe.Util.to_string"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_char -> "(fun j -> (Yojson.Safe.Util.to_string j).[0])"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_unit -> "(fun _ -> ())"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_list ->
      "(fun j -> List.map (" ^ dec env recSet seen a ^ ") (Yojson.Safe.Util.to_list j))"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_option ->
      "(fun j -> match j with `Null -> None | _ -> Some ((" ^ dec env recSet seen a ^ ") j))"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_array ->
      "(fun j -> Array.of_list (List.map (" ^ dec env recSet seen a ^ ") (Yojson.Safe.Util.to_list j)))"
  | Types.Tconstr (p, args, _) ->
      let k = instKey t in
      if List.mem k recSet then "ofJson_" ^ k else decNamed env recSet seen k (Env.find_type p env) args
  | Types.Ttuple ts ->
      let ts = List.map snd ts in
      let pat = String.concat "; " (List.mapi (fun i _ -> Printf.sprintf "v%d" i) ts) in
      let items = List.mapi (fun i t -> "(" ^ dec env recSet seen t ^ ") v" ^ string_of_int i) ts in
      "(fun j -> match Yojson.Safe.Util.to_list j with [ " ^ pat ^ " ] -> (" ^ String.concat ", " items
      ^ ") | _ -> failwith \"bad tuple\")"
  | _ -> failwith "unsupported [@rpc] type (decoder)"

and decNamed env recSet seen key (d: Types.type_declaration) args =
  if List.mem key seen then failwith ("recursive [@rpc] type: " ^ key);
  let sub = withSub d args in
  match d.type_kind with
  | Types.Type_abstract _ ->
      (match d.type_manifest with
       | Some m -> dec env recSet seen (subst sub m)
       | None -> failwith ("unsupported abstract [@rpc] type: " ^ key))
  | Types.Type_record (labels, _) ->
      let fields =
        List.map
          (fun (l: Types.label_declaration) ->
            let fn = Ident.name l.ld_id in
            Printf.sprintf "%s = (%s) (List.assoc %S o)" fn
              (dec env recSet (key :: seen) (subst sub l.ld_type)) fn)
          labels
      in
      "(fun j -> let o = Yojson.Safe.Util.to_assoc j in { " ^ String.concat "; " fields ^ " })"
  | Types.Type_variant (ctors, _) ->
      let cases =
        ctors
        |> List.map (fun (c: Types.constructor_declaration) ->
               let cname = Ident.name c.cd_id in
               if isConstCtor c then Printf.sprintf "%S -> %s" cname cname
               else
                 let ts = List.map (subst sub) (Option.get (ctorArgs c)) in
                 let args =
                   List.mapi
                     (fun i t ->
                       Printf.sprintf "((%s) (List.assoc %S o))" (dec env recSet (key :: seen) t)
                         ("$" ^ string_of_int i))
                     ts
                 in
                 let arg = match args with [ a ] -> a | _ -> "(" ^ String.concat ", " args ^ ")" in
                 Printf.sprintf "%S -> %s %s" cname cname arg)
      in
      "(fun j -> let o = Yojson.Safe.Util.to_assoc j in match Yojson.Safe.Util.to_string (List.assoc \"$\" o) with "
      ^ String.concat " | " cases ^ " | _ -> failwith \"bad variant\")"
  | _ -> failwith ("unsupported [@rpc] type: " ^ key)

type inst =
    { key : string;
      decl : Types.type_declaration;
      args : Types.type_expr list }

(* Collect the concrete record/variant instantiations reachable from a set of
   types, substituting type arguments as we descend. *)
let collectTypes env (ts: Types.type_expr list) : inst list =
  let seen = Hashtbl.create 32 in
  let order = ref [] in
  let rec go t =
    if Hashtbl.length seen > 1000 then failwith "too many [@rpc] type instantiations (polymorphic recursion?)";
    match Types.get_desc t with
    | Types.Tconstr (p, args, _) ->
        List.iter go args;
        if unsupportedBoxed p then failwith ("unsupported [@rpc] type (boxed integer): " ^ Path.name p);
        if not (builtinPath p) then (
          let k = instKey t in
          if not (Hashtbl.mem seen k) then (
            Hashtbl.add seen k ();
            let d = Env.find_type p env in
            order := { key = k; decl = d; args } :: !order;
            let sub = withSub d args in
            match d.type_kind with
            | Types.Type_record (ls, _) -> List.iter (fun (l: Types.label_declaration) -> go (subst sub l.ld_type)) ls
            | Types.Type_variant (cs, _) ->
                List.iter
                  (fun (c: Types.constructor_declaration) ->
                    match ctorArgs c with Some ts -> List.iter (fun x -> go (subst sub x)) ts | None -> ())
                  cs
            | Types.Type_abstract _ -> (match d.type_manifest with Some m -> go (subst sub m) | None -> ())
            | _ -> ()))
    | Types.Ttuple ts -> List.iter (fun (_, x) -> go x) ts
    | Types.Tarrow (_, a, b, _) -> go a; go b
    | _ -> ()
  in
  List.iter go ts;
  List.rev !order

let directRefKeys (i: inst) : string list =
  let sub = withSub i.decl i.args in
  let acc = ref [] in
  let rec go t =
    match Types.get_desc t with
    | Types.Tconstr (p, args, _) -> if builtinPath p then List.iter go args else acc := instKey t :: !acc
    | Types.Ttuple ts -> List.iter (fun (_, x) -> go x) ts
    | Types.Tarrow (_, a, b, _) -> go a; go b
    | _ -> ()
  in
  (match i.decl.type_kind with
   | Types.Type_record (ls, _) -> List.iter (fun (l: Types.label_declaration) -> go (subst sub l.ld_type)) ls
   | Types.Type_variant (cs, _) ->
       List.iter
         (fun (c: Types.constructor_declaration) ->
           match ctorArgs c with Some ts -> List.iter (fun x -> go (subst sub x)) ts | None -> ())
         cs
   | Types.Type_abstract _ -> (match i.decl.type_manifest with Some m -> go (subst sub m) | None -> ())
   | _ -> ());
  !acc

(* Keys of instantiations that are part of a reference cycle. *)
let recursiveKeys (collected: inst list) =
  let refs = collected |> List.map (fun i -> i.key, directRefKeys i) in
  let lookup k = try List.assoc k refs with Not_found -> [] in
  let reaches start =
    let seen = Hashtbl.create 16 in
    let rec go k =
      if k = start then true
      else if Hashtbl.mem seen k then false
      else (Hashtbl.add seen k (); List.exists go (lookup k))
    in
    List.exists go (lookup start)
  in
  collected |> List.filter (fun i -> reaches i.key) |> List.map (fun i -> i.key)

let helperDefs env recSet (collected: inst list) : string =
  let ds = collected |> List.filter (fun i -> List.mem i.key recSet) in
  let defs =
    ds
    |> List.concat_map (fun i ->
           [ "toJson_" ^ i.key ^ " = " ^ encNamed env recSet [] i.key i.decl i.args;
             "ofJson_" ^ i.key ^ " = " ^ decNamed env recSet [] i.key i.decl i.args ])
  in
  match defs with
  | [] -> ""
  | first :: rest -> "let rec " ^ first ^ "\n" ^ String.concat "" (List.map (fun d -> "and " ^ d ^ "\n") rest)

let ofJson env recSet (t: Types.type_expr) = dec env recSet [] t
let toJson env recSet (t: Types.type_expr) = enc env recSet [] t

(* --- TypeScript declarations (.d.ts) for [@export] --- *)

let rec dtsType env (defs: (string, string * string) Hashtbl.t) (t: Types.type_expr) : string =
  match Types.get_desc t with
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_int -> "number"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_float -> "number"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_bool -> "boolean"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_string -> "string"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_char -> "string"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_unit -> "null"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_list -> dtsType env defs a ^ "[]"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_array -> dtsType env defs a ^ "[]"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_option -> "(" ^ dtsType env defs a ^ ") | null"
  | Types.Tconstr (p, args, _) ->
      let d = Env.find_type p env in
      (match d.type_kind with
       | Types.Type_abstract _ ->
           (match d.type_manifest with
            | Some m -> dtsType env defs (subst (withSub d args) m)
            | None -> "unknown")
       | _ ->
           let k = instKey t in
           if not (Hashtbl.mem defs k) then (
             Hashtbl.add defs k (typeName p, "");
             let sub = withSub d args in
             let body =
               match d.type_kind with
               | Types.Type_record (ls, _) ->
                   "{ "
                   ^ String.concat "; "
                       (List.map
                          (fun (l: Types.label_declaration) ->
                            Printf.sprintf "%s: %s" (Ident.name l.ld_id) (dtsType env defs (subst sub l.ld_type)))
                          ls)
                   ^ " }"
               | Types.Type_variant (cs, _) ->
                   String.concat " | "
                     (List.map
                        (fun (c: Types.constructor_declaration) ->
                          let nm = Ident.name c.cd_id in
                          if isConstCtor c then Printf.sprintf "{ $: \"%s\" }" nm
                          else
                            let ts = List.map (subst sub) (Option.get (ctorArgs c)) in
                            "{ $: \""
                            ^ nm
                            ^ "\"; "
                            ^ String.concat "; "
                                (List.mapi (fun i t -> Printf.sprintf "$%d: %s" i (dtsType env defs t)) ts)
                            ^ " }")
                        cs)
               | _ -> "unknown"
             in
             Hashtbl.replace defs k (typeName p, body));
           typeName p)
  | Types.Ttuple ts -> "[" ^ String.concat ", " (List.map (fun (_, x) -> dtsType env defs x) ts) ^ "]"
  | _ -> "unknown"



(* --- Type descriptors (JS-side marshalling) ---
   A compact, recursion-aware description of a type in the external
   representation, consumed by the runtime to marshal OCaml values to/from JS.
   Named record/variant types live in a shared table and are referenced by key. *)

let rec descr env (defs: (string, Yojson.Safe.t) Hashtbl.t) (t: Types.type_expr) : Yojson.Safe.t =
  match Types.get_desc t with
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_int -> `Assoc [ ("k", `String "int") ]
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_bool -> `Assoc [ ("k", `String "bool") ]
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_float -> `Assoc [ ("k", `String "float") ]
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_string -> `Assoc [ ("k", `String "string") ]
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_char -> `Assoc [ ("k", `String "char") ]
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_unit -> `Assoc [ ("k", `String "unit") ]
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_list ->
      `Assoc [ ("k", `String "list"); ("e", descr env defs a) ]
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_option ->
      `Assoc [ ("k", `String "option"); ("e", descr env defs a) ]
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_array ->
      `Assoc [ ("k", `String "array"); ("e", descr env defs a) ]
  | Types.Tconstr (p, args, _) ->
      let d = Env.find_type p env in
      (match d.type_kind with
       | Types.Type_abstract _ ->
           (match d.type_manifest with
            | Some m -> descr env defs (subst (withSub d args) m)
            | None -> failwith ("unsupported [@rpc] type: " ^ instKey t))
       | _ ->
      let k = instKey t in
      if not (Hashtbl.mem defs k) then (
        Hashtbl.add defs k (`Assoc [ ("k", `String "pending") ]);
        let sub = withSub d args in
        let def =
          match d.type_kind with
          | Types.Type_record (ls, _) ->
              `Assoc
                [ ("key", `String k); ("kind", `String "record");
                  ( "fields",
                    `List
                      (List.map
                         (fun (l: Types.label_declaration) ->
                           `List [ `String (Ident.name l.ld_id); descr env defs (subst sub l.ld_type) ])
                         ls) ) ]
          | Types.Type_variant (cs, _) ->
              let consts = List.filter isConstCtor cs in
              let nonc = List.filter (fun c -> not (isConstCtor c)) cs in
              let cases =
                cs
                |> List.map (fun (c: Types.constructor_declaration) ->
                       let nm = Ident.name c.cd_id in
                       if isConstCtor c then `List [ `String nm; `Int (indexOf c consts); `List [] ]
                       else
                         let ts = List.map (subst sub) (Option.get (ctorArgs c)) in
                         `List [ `String nm; `Int (indexOf c nonc); `List (List.map (descr env defs) ts) ])
              in
              `Assoc [ ("key", `String k); ("kind", `String "variant"); ("cases", `List cases) ]
          | _ -> failwith ("unsupported [@rpc] type: " ^ k)
        in
        Hashtbl.replace defs k def);
      `Assoc [ ("k", `String "named"); ("key", `String k) ])
  | Types.Ttuple ts ->
      `Assoc [ ("k", `String "tuple"); ("e", `List (List.map (fun (_, x) -> descr env defs x) ts)) ]
  | _ -> failwith "unsupported [@rpc] type (descriptor)"


let rec arrows (t: Types.type_expr) : Types.type_expr list * Types.type_expr =
  match Types.get_desc t with
  | Types.Tarrow (_, a, b, _) ->
      let ps, r = arrows b in
      (a :: ps, r)
  | _ -> ([], t)

let renderDts env (files: (string, Types.type_expr) Hashtbl.t) (exp: string list) : string =
  let defs = Hashtbl.create 32 in
  let sigs =
    exp
    |> List.map (fun name ->
           let ty = Hashtbl.find files name in
           let ps, ret = arrows ty in
           if ps = [] then Printf.sprintf "export const %s: %s;" name (dtsType env defs ty)
           else
             Printf.sprintf "export function %s(%s): %s;" name
               (String.concat ", " (List.mapi (fun i p -> Printf.sprintf "a%d: %s" i (dtsType env defs p)) ps))
               (dtsType env defs ret))
  in
  let buf = Buffer.create 512 in
  Buffer.add_string buf "// Generated by wsocaml-frontend. Do not edit.\n";
  Hashtbl.iter (fun _ (n, body) -> Buffer.add_string buf (Printf.sprintf "export type %s = %s;\n" n body)) defs;
  List.iter (fun sg -> Buffer.add_string buf (sg ^ "\n")) sigs;
  Buffer.contents buf

let endsWith suffix s =
  let ls = String.length s and lf = String.length suffix in
  ls >= lf && String.sub s (ls - lf) lf = suffix

(* An [@rpc] function returns `'a Async.t`; the server handler unwraps it. *)
let asyncElem (t: Types.type_expr) : Types.type_expr option =
  match Types.get_desc t with
  | Types.Tconstr (p, [ a ], _) ->
      let n = Path.name p in
      if n = "Async.t" || endsWith ".Async.t" n then Some a else None
  | _ -> None

let typedTypes (typed: Typedtree.structure) : (string, Types.type_expr) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (item: Typedtree.structure_item) ->
      match item.str_desc with
      | Typedtree.Tstr_value (_, vbs) ->
          List.iter
            (fun (vb: Typedtree.value_binding) ->
              match vb.vb_pat.pat_desc with
              | Typedtree.Tpat_var (id, _, _) -> Hashtbl.replace tbl (Ident.name id) vb.vb_expr.exp_type
              | _ -> ())
            vbs
      | _ -> ())
    typed.str_items;
  tbl

let stripMarkers (attrs: Parsetree.attributes) =
  List.filter
    (fun (a: Parsetree.attribute) ->
      a.attr_name.txt <> "javascript" && a.attr_name.txt <> "rpc"
      && a.attr_name.txt <> "export" && a.attr_name.txt <> "client" && a.attr_name.txt <> "website")
    attrs

let openName (od: Parsetree.open_declaration) =
  match od.popen_expr.pmod_desc with
  | Parsetree.Pmod_ident { txt = lid; _ } ->
      (match Longident.flatten lid with
       | n :: _ -> Some n
       | [] -> None)
  | _ -> None

let serverItems (ast: Parsetree.structure) (js: string list) : Parsetree.structure =
  List.filter_map
    (fun (item: Parsetree.structure_item) ->
      match item.pstr_desc with
      (* Keep WebSharper_UI opens: on the server `WebSharper_UI` is the native
         shadow (runtimes/ocaml/webSharper_UI.ml), the same module name as the
         client binding, so the source typechecks on both tiers. Drop other
         generated-binding opens (e.g. `open WebSharper_JavaScript`). *)
      | Parsetree.Pstr_open od ->
          let keep n =
            let has (pre : string) (n : string) =
              String.length n >= String.length pre && String.sub n 0 (String.length pre) = pre
            in
            has "WebSharper_UI" n || has "WebSharper_Server" n || has "WebSharper_ClientServer" n
          in
          (match openName od with
           | Some n when keep n -> Some item
           | Some n when String.length n >= 11 && String.sub n 0 11 = "WebSharper_" -> None
           | _ -> Some item)
      | Parsetree.Pstr_value (rf, vbs) ->
          let kept =
            vbs
            |> List.filter (fun (vb: Parsetree.value_binding) ->
                   match vb.pvb_pat.ppat_desc with
                   | Parsetree.Ppat_var { txt = n; _ } -> not (List.mem n js)
                   | _ -> false)
            |> List.map (fun (vb: Parsetree.value_binding) ->
                   { vb with pvb_attributes = stripMarkers vb.pvb_attributes })
          in
          if kept = [] then None
          else Some { item with pstr_desc = Parsetree.Pstr_value (rf, kept) }
      | _ -> Some item)
    ast

let prettyStructure (items: Parsetree.structure) : string =
  let buf = Buffer.create 512 in
  let fmt = Format.formatter_of_buffer buf in
  Pprintast.structure fmt items;
  Format.pp_print_flush fmt ();
  Buffer.contents buf

let emitServer (path: string) (ast: Parsetree.structure) (typed: Typedtree.structure) (env: Env.t)
    (js: string list) (rpcs: string list) (clients: string list) (website: string option) (unitName: string)
    (static_dir: string option) =
  let files = typedTypes typed in
  let sigs =
    rpcs |> List.map (fun name ->
      let ps, ret = arrows (Hashtbl.find files name) in
      let ret = match asyncElem ret with Some inner -> inner | None -> ret in
      (name, ps, ret))
  in
  let collected = collectTypes env (List.concat_map (fun (_, ps, ret) -> ps @ [ ret ]) sigs) in
  let recSet = recursiveKeys collected in
  let sb = Buffer.create 2048 in
  Buffer.add_string sb "(* Generated native RPC server. Do not edit. *)\n";
  Buffer.add_string sb (prettyStructure (serverItems ast (List.filter (fun n -> not (List.mem n clients)) js)));
  Buffer.add_string sb "\n";
  Buffer.add_string sb (helperDefs env recSet collected);
  Buffer.add_string sb "let () =\n";
  List.iter
    (fun (name, ps, ret) ->
      let vars = List.mapi (fun i p -> Printf.sprintf "a%d" i, ofJson env recSet p) ps in
      let base =
        String.concat " " (name :: List.map (fun (v, c) -> Printf.sprintf "((%s) %s)" c v) vars)
      in
      let base =
        let _, original = arrows (Hashtbl.find files name) in
        match asyncElem original with
        | Some _ -> Printf.sprintf "Async.run_sync (%s)" base
        | None -> base
      in
      let pattern = List.map fst vars |> String.concat "; " in
      Buffer.add_string sb
        (Printf.sprintf
           "  Wsrpc.register %S (fun (args : Yojson.Safe.t list) ->\n    match args with\n    | [ %s ] -> (%s) (%s)\n    | _ -> failwith \"rpc %s: wrong arity\");\n"
           name pattern (toJson env recSet ret) base name))
    sigs;
  (match website with
   | Some w ->
       let static_arg = match static_dir with Some d -> Printf.sprintf " ~static:%S" d | None -> "" in
       Buffer.add_string sb
         (Printf.sprintf "  WebSharper_Server.Server.serve ~port:8123 ~bundle:%S%s %s\n" unitName static_arg w)
   | None ->
       if clients = [] then
         Buffer.add_string sb
           "  Wsrpc.serve ~port:8123 (fun _ -> { Wsrpc.status = 404; headers = []; body = \"not found\" })\n"
       else (
         Buffer.add_string sb "  Ssr.regions_reset ();\n";
         List.iter (fun n -> Buffer.add_string sb (Printf.sprintf "  %s ();\n" n)) clients;
         Buffer.add_string sb
           "  Wsrpc.serve ~port:8123 (fun _ -> { Wsrpc.status = 200; headers = [ (\"Content-Type\", \"text/html; charset=utf-8\") ]; body = Ssr.page ~title:\"wsocaml\" ~scripts:[ \"/Main.js\" ] () })\n"));
  let ch = open_out path in
  output_string ch (Buffer.contents sb);
  close_out ch


(* --- [@endpoint] / Sitelet.Infer ------------------------------------------
   The endpoint is a variant whose constructors carry
   [@endpoint "METHOD /path/@arg/..."]; each `@` variable is (positionally) an
   argument of that constructor. `Sitelet.Infer (fun ctx ep -> ...)` is expanded
   into `Sitelet.make route link (fun ctx ep -> ...)` with a generated router and
   URL builder. *)

let attrString (attrs: Parsetree.attributes) (name: string) : string option =
  List.find_map
    (fun (a: Parsetree.attribute) ->
      if a.attr_name.txt = name then
        match a.attr_payload with
        | Parsetree.PStr
            [ { pstr_desc = Parsetree.Pstr_eval ({ pexp_desc = Parsetree.Pexp_constant { pconst_desc = Parsetree.Pconst_string (str, _, _); _ }; _ }, _); _ } ] ->
            Some str
        | _ -> None
      else None)
    attrs

let stripEndpointAttrs (attrs: Parsetree.attributes) =
  List.filter (fun (a: Parsetree.attribute) -> a.attr_name.txt <> "endpoint") attrs

let coreName (ct: Parsetree.core_type) =
  match ct.ptyp_desc with
  | Parsetree.Ptyp_constr ({ txt = Longident.Lident n; _ }, []) -> n
  | _ -> "?"

let splitMethod (ep: string) =
  match String.index_opt ep ' ' with
  | Some i -> String.sub ep 0 i, String.trim (String.sub ep (i + 1) (String.length ep - i - 1))
  | None -> "GET", ep

let parseArg (ty: string) (v: string) =
  match ty with
  | "int" -> Printf.sprintf "int_of_string %s" v
  | "string" -> v
  | "bool" -> Printf.sprintf "(%s = \"true\")" v
  | "float" -> Printf.sprintf "float_of_string %s" v
  | _ -> Printf.sprintf "(failwith \"unsupported @-arg type %s\")" ty

let fmtArg (ty: string) (v: string) =
  match ty with
  | "int" -> Printf.sprintf "string_of_int %s" v
  | "string" -> v
  | "bool" -> Printf.sprintf "(if %s then \"true\" else \"false\")" v
  | "float" -> Printf.sprintf "string_of_float %s" v
  | _ -> v

let endpointCtorsOf (ast: Parsetree.structure) =
  List.find_map
    (fun (item: Parsetree.structure_item) ->
      match item.pstr_desc with
      | Parsetree.Pstr_type (_, decls) ->
          List.find_map
            (fun (td: Parsetree.type_declaration) ->
              match td.ptype_kind with
              | Parsetree.Ptype_variant ctors
                when List.exists (fun (c: Parsetree.constructor_declaration) -> attrString c.pcd_attributes "endpoint" <> None) ctors ->
                  Some ctors
              | _ -> None)
            decls
      | _ -> None)
    ast

let ctorArgsOf (c: Parsetree.constructor_declaration) =
  match c.pcd_args with
  | Parsetree.Pcstr_tuple ts -> ts
  | Parsetree.Pcstr_record ls -> List.map (fun (l: Parsetree.label_declaration) -> l.pld_type) ls

let genRoute (ctors: Parsetree.constructor_declaration list) =
  let cases =
    List.map
      (fun (c: Parsetree.constructor_declaration) ->
        let cname = c.pcd_name.txt in
        let ep = Option.get (attrString c.pcd_attributes "endpoint") in
        let meth, path = splitMethod ep in
        let segs = List.filter (fun x -> x <> "") (String.split_on_char '/' path) in
        let args = ctorArgsOf c in
        let k = ref 0 in
        let pats =
          List.map
            (fun seg ->
              if String.length seg > 0 && seg.[0] = '@' then (
                let v = Printf.sprintf "v%d" !k in
                incr k;
                v)
              else Printf.sprintf "%S" seg)
            segs
        in
        let parsed = List.mapi (fun i t -> parseArg (coreName t) (Printf.sprintf "v%d" i)) args in
        let applied =
          match parsed with
          | [] -> cname
          | [ x ] -> Printf.sprintf "%s (%s)" cname x
          | xs -> Printf.sprintf "%s (%s)" cname (String.concat ", " xs)
        in
        Printf.sprintf "  | %S, [ %s ] -> (try Some (%s) with _ -> None)" meth (String.concat "; " pats) applied)
      ctors
  in
  Printf.sprintf
    "(fun (req : WebSharper_Server.request) ->\n  let segs = Stdlib.List.filter (fun s -> s <> \"\") (Stdlib.String.split_on_char '/' req.path) in\n  match req.method_, segs with\n%s\n  | _ -> None)"
    (String.concat "\n" cases)

let genLink (ctors: Parsetree.constructor_declaration list) =
  let cases =
    List.map
      (fun (c: Parsetree.constructor_declaration) ->
        let cname = c.pcd_name.txt in
        let ep = Option.get (attrString c.pcd_attributes "endpoint") in
        let _, path = splitMethod ep in
        let segs = List.filter (fun x -> x <> "") (String.split_on_char '/' path) in
        let args = ctorArgsOf c in
        let vars = List.mapi (fun i _ -> Printf.sprintf "v%d" i) args in
        let pat =
          match vars with
          | [] -> cname
          | [ v ] -> Printf.sprintf "%s %s" cname v
          | vs -> Printf.sprintf "%s (%s)" cname (String.concat ", " vs)
        in
        let k = ref 0 in
        let parts =
          List.map
            (fun seg ->
              if String.length seg > 0 && seg.[0] = '@' then (
                let i = !k in
                incr k;
                Printf.sprintf "(%s)" (fmtArg (coreName (List.nth args i)) (Printf.sprintf "v%d" i)))
              else Printf.sprintf "%S" seg)
            segs
        in
        let expr = match parts with [] -> "\"/\"" | _ -> "\"/\" ^ " ^ String.concat " ^ \"/\" ^ " parts in
        Printf.sprintf "  | %s -> %s" pat expr)
      ctors
  in
  "(function\n" ^ String.concat "\n" cases ^ ")"

let transformInfer (ast: Parsetree.structure) : Parsetree.structure =
  match endpointCtorsOf ast with
  | None -> ast
  | Some ctors ->
      let route_e = Parse.expression (Lexing.from_string (genRoute ctors)) in
      let link_e = Parse.expression (Lexing.from_string (genLink ctors)) in
      let mapper =
        { Ast_mapper.default_mapper with
          structure_item =
            (fun self (item: Parsetree.structure_item) ->
              match item.pstr_desc with
              | Parsetree.Pstr_type (rf, decls) ->
                  let decls =
                    List.map
                      (fun (td: Parsetree.type_declaration) ->
                        match td.ptype_kind with
                        | Parsetree.Ptype_variant cs ->
                            { td with ptype_kind = Parsetree.Ptype_variant (List.map (fun (c: Parsetree.constructor_declaration) -> { c with pcd_attributes = stripEndpointAttrs c.pcd_attributes }) cs) }
                        | _ -> td)
                      decls
                  in
                  Ast_mapper.default_mapper.structure_item self { item with pstr_desc = Parsetree.Pstr_type (rf, decls) }
              | _ -> Ast_mapper.default_mapper.structure_item self item);
          expr =
            (fun self (e: Parsetree.expression) ->
              let isInfer (f: Parsetree.expression) =
                match f.pexp_desc with
                | Parsetree.Pexp_ident { txt = lid; _ } ->
                    (match Longident.flatten lid with
                     | [ "Sitelet"; ("Infer" | "infer") ] -> true
                     | _ -> false)
                | Parsetree.Pexp_construct ({ txt = lid; _ }, None) ->
                    (match Longident.flatten lid with
                     | [ "Sitelet"; ("Infer" | "infer") ] -> true
                     | _ -> false)
                | _ -> false
              in
              let mk handler =
                let make_e : Parsetree.expression =
                  { Parsetree.pexp_desc = Parsetree.Pexp_ident { txt = Option.get (Longident.unflatten [ "Sitelet"; "make" ]); loc = e.pexp_loc };
                    pexp_loc = e.pexp_loc;
                    pexp_loc_stack = [];
                    pexp_attributes = [] }
                in
                { e with
                  pexp_desc =
                    Parsetree.Pexp_apply
                      (make_e, [ (Asttypes.Nolabel, route_e); (Asttypes.Nolabel, link_e); (Asttypes.Nolabel, handler) ]) }
              in
              match e.pexp_desc with
              | Parsetree.Pexp_construct ({ txt = lid; _ }, Some handler)
                when (match Longident.flatten lid with [ "Sitelet"; ("Infer" | "infer") ] -> true | _ -> false) ->
                  Ast_mapper.default_mapper.expr self (mk handler)
              | Parsetree.Pexp_apply (f, [ (_, handler) ]) when isInfer f -> Ast_mapper.default_mapper.expr self (mk handler)
              | _ -> Ast_mapper.default_mapper.expr self e);
        }
      in
      mapper.structure mapper ast


(* --- WebSharper_ClientServer.client / hydrate -------------------------------
   `client (fun () -> view)` / `hydrate (fun () -> view)`: the argument is lifted
   into a top-level [@client] binding under a stable opaque id, and the call is
   replaced by a marker (`__client`/`__hydrate <id>`) embedded in the page. The
   server renders the marker (hydrate also server-renders the view); the client
   runs the binding into the `data-ws-key` region. Fragments must be closed. *)

let transformClientServer (ast: Parsetree.structure) : Parsetree.structure =
  let frags = ref [] in
  let csCall (f: Parsetree.expression) =
    match f.pexp_desc with
    | Parsetree.Pexp_ident { txt = lid; _ } -> (
        match Longident.flatten lid with
        | [ "WebSharper_ClientServer"; "client" ] | [ "client" ] -> Some false
        | [ "WebSharper_ClientServer"; "hydrate" ] | [ "hydrate" ] -> Some true
        | _ -> None)
    | _ -> None
  in
  let id_of (e: Parsetree.expression) =
    let buf = Buffer.create 64 in
    let fmt = Format.formatter_of_buffer buf in
    Pprintast.expression fmt e;
    Format.pp_print_flush fmt ();
    let h = Hashtbl.hash (Buffer.contents buf) in
    "ws" ^ string_of_int (if h < 0 then -h else h)
  in
  let subst (arg: Parsetree.expression) (e: Parsetree.expression) =
    let m =
      { Ast_mapper.default_mapper with
        expr =
          (fun self (x: Parsetree.expression) ->
            match x.pexp_desc with
            | Parsetree.Pexp_ident { txt = Longident.Lident "zzz_arg"; _ } -> arg
            | _ -> Ast_mapper.default_mapper.expr self x);
      }
    in
    m.expr m e
  in
  (* Server marker: `__client id` (placeholder) or `__hydrate id (fun () -> view)`. *)
  let marker mode id (arg: Parsetree.expression) =
    let s =
      if mode then Printf.sprintf "WebSharper_ClientServer.__hydrate %S (zzz_arg)" id
      else Printf.sprintf "WebSharper_ClientServer.__client %S" id
    in
    let e = Parse.expression (Lexing.from_string s) in
    if mode then subst arg e else e
  in
  (* Client binding: `fun () -> WebSharper_UI.Doc.runById id (view)`. *)
  let binding_value id (arg: Parsetree.expression) =
    let s = Printf.sprintf "fun () -> WebSharper_UI.Doc.runById %S (zzz_arg ())" id in
    subst arg (Parse.expression (Lexing.from_string s))
  in
  let mapper =
    { Ast_mapper.default_mapper with
      expr =
        (fun self (e: Parsetree.expression) ->
          match e.pexp_desc with
          | Parsetree.Pexp_apply (f, [ (_, arg) ]) when csCall f <> None ->
              (* Map the fragment first so inner rewrites (e.g. `on.x`) are applied
                 in both the marker and the lifted binding. *)
              let arg = Ast_mapper.default_mapper.expr self arg in
              let id = id_of arg in
              frags := (id, arg) :: !frags;
              Ast_mapper.default_mapper.expr self (marker (Option.get (csCall f)) id arg)
          (* `on.x` -> `On.x` (WebSharper.UI's `On` module). *)
          | Parsetree.Pexp_field
              ( { Parsetree.pexp_desc = Parsetree.Pexp_ident { txt = Longident.Lident "on"; _ }; _ },
                { txt = fld; _ } ) ->
              let fname = match List.rev (Longident.flatten fld) with x :: _ -> x | [] -> "" in
              let id =
                { Parsetree.pexp_desc = Parsetree.Pexp_ident { txt = Option.get (Longident.unflatten [ "On"; fname ]); loc = e.pexp_loc };
                  pexp_loc = e.pexp_loc;
                  pexp_loc_stack = [];
                  pexp_attributes = [] }
              in
              Ast_mapper.default_mapper.expr self id
          | _ -> Ast_mapper.default_mapper.expr self e);
    }
  in
  let mapped = mapper.structure mapper ast in
  if !frags = [] then mapped
  else
    let bindings =
      List.rev_map
        (fun ((id, arg): string * Parsetree.expression) ->
          let loc = arg.pexp_loc in
          let pat =
            { Parsetree.ppat_desc = Parsetree.Ppat_var { txt = id; loc };
              ppat_loc = loc; ppat_loc_stack = []; ppat_attributes = [] }
          in
          let client_attr =
            { Parsetree.attr_name = { txt = "client"; loc }; attr_payload = Parsetree.PStr []; attr_loc = loc }
          in
          let vb =
            { Parsetree.pvb_pat = pat; pvb_expr = binding_value id arg; pvb_attributes = [ client_attr ]; pvb_loc = loc; pvb_constraint = None }
          in
          { Parsetree.pstr_desc = Parsetree.Pstr_value (Asttypes.Nonrecursive, [ vb ]); pstr_loc = loc })
        !frags
    in
    (* Insert after the opens/types, before the first value binding, so the
       (closed) fragments can use the opened modules but are defined before any
       use in a page/view value. *)
    let rec insert acc = function
      | [] -> List.rev_append acc bindings
      | (({ Parsetree.pstr_desc = Parsetree.Pstr_value _; _ } :: _) as rest) -> List.rev_append acc (bindings @ rest)
      | item :: rest -> insert (item :: acc) rest
    in
    insert [] mapped

let () =
  let input = ref ""
  and output = ref ""
  and unit_name = ref ""
  and includes = ref []
  and emit_server = ref None
  and dts = ref None
  and static_dir = ref None in
  Arg.parse
    [
      ("--input", Arg.Set_string input, ".ml input");
      ("--output", Arg.Set_string output, "IR output");
      ("--unit", Arg.Set_string unit_name, "unit name");
      ("--emit-server", Arg.String (fun x -> emit_server := Some x), "emit a native RPC server .ml");
      ("--dts", Arg.String (fun x -> dts := Some x), "emit TypeScript declarations for [@export]");
      ("--static", Arg.String (fun x -> static_dir := Some x), "static assets directory for the server");
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
    let ast = transformClientServer (transformInfer (parse !input)) in
    checkBoundary ast;
    let js, rpc, srv = clientMarks ast in
    let exp = exportMarks ast in
    let cli = clientNames ast in
    let website = match websiteMarks ast with [] -> None | w :: _ -> Some w in
    let u =
      if !unit_name <> "" then !unit_name
      else String.capitalize_ascii (Filename.remove_extension (Filename.basename !input))
    in
    let typed, _, _, _, typedEnv = Typemod.type_structure env ast in
    (match !emit_server with
    | Some p ->
        emitServer p ast typed typedEnv js rpc cli website u !static_dir;
        exit 0
    | None -> ());
    let program = Translmod.transl_implementation u (typed, Tcoerce_none) in
    let files = typedTypes typed in
    let rpcMeta =
      rpc
      |> List.map (fun name ->
             let ty = Hashtbl.find files name in
             let ps, ret = arrows ty in
             let ret = match asyncElem ret with Some i -> i | None -> ret in
             let defs = Hashtbl.create 16 in
             let args = List.map (descr typedEnv defs) ps in
             let result = descr typedEnv defs ret in
             let types = `List (Hashtbl.fold (fun _ v acc -> v :: acc) defs []) in
             let meta = Yojson.Safe.to_string (`Assoc [ ("types", types); ("args", `List args); ("result", result) ]) in
             `Assoc [ ("name", `String name); ("meta", `String meta) ])
    in
    let topIndex =
      let i = ref 0 and acc = ref [] in
      List.iter
        (fun (item: Typedtree.structure_item) ->
          match item.str_desc with
          | Typedtree.Tstr_value (_, vbs) ->
              List.iter
                (fun (vb: Typedtree.value_binding) ->
                  match vb.vb_pat.pat_desc with
                  | Typedtree.Tpat_var (id, _, _) ->
                      acc := (Ident.name id, !i) :: !acc;
                      incr i
                  | _ -> ())
                vbs
          | _ -> ())
        typed.str_items;
      List.rev !acc
    in
    let exports =
      exp
      |> List.map (fun name ->
             let ty = Hashtbl.find files name in
             let ps, ret = arrows ty in
             let isFn = ps <> [] in
             let defs = Hashtbl.create 16 in
             let args = if isFn then List.map (descr typedEnv defs) ps else [] in
             let result = descr typedEnv defs (if isFn then ret else ty) in
             let types = `List (Hashtbl.fold (fun _ v acc -> v :: acc) defs []) in
             let meta =
               Yojson.Safe.to_string
                 (`Assoc [ ("types", types); ("args", `List args); ("result", result) ])
             in
             let index = try List.assoc name topIndex with Not_found -> -1 in
             `Assoc
               [ ("name", `String name); ("index", `Int index); ("arity", `Int (List.length ps));
                 ("meta", `String meta) ])
    in
    (match !dts with
     | Some p ->
         let ch = open_out p in
         output_string ch (renderDts typedEnv files exp);
         close_out ch
     | None -> ());
    let json =
      `Assoc
        [
          ("schema", `String "wsocaml-ir-5");
          ("unit", `String u);
          ("moduleIdent", `String (Ident.name program.module_ident));
          ("mainModuleBlockSize", `Int program.main_module_block_size);
          ("javascript", `List (List.map (fun n -> `String n) js));
          ("rpc", `List (List.map (fun n -> `String n) rpc));
          ("server", `List (List.map (fun n -> `String n) srv));
          ("rpcs", `List rpcMeta);
          ("exports", `List exports);
          ( "clients",
            `List
              (cli
              |> List.map (fun name ->
                     let index = try List.assoc name topIndex with Not_found -> -1 in
                     `Assoc
                       [ ("name", `String name); ("key", `String name); ("index", `Int index) ])) );
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
