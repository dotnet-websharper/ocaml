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
                  if List.mem "javascript" a then js := n :: !js
                  else if List.mem "rpc" a then rpc := n :: !rpc
                  else srv := n :: !srv
              | _ -> ())
            vbs
      | _ -> ())
    ast;
  (List.rev !js, List.rev !rpc, List.rev !srv)

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
                    if List.mem "javascript" a then "js"
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

(* [@rpc] codecs. Values travel in their OCaml runtime representation, so the
   client — which hands raw OCaml values to `rpcCall` — needs no codec: a block
   is `{"$tag": t, "0": f0, ...}`, a list is a cons chain (`[]` is `0`), and
   immediates (int/bool/char/unit) are JSON numbers. Arrays are JS arrays.
   Only the native server converts between real OCaml values and this
   representation. Recursive record/variant types get named helper codecs
   (`toJson_<name>`/`ofJson_<name>`) emitted in a `let rec` group. *)

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

(* A tagged block: `{"$tag": tag, "0": f0, "1": f1, ...}`. *)
let block tag (fields: string list) =
  let parts =
    Printf.sprintf "(\"$tag\", `Int %d)" tag
    :: List.mapi (fun i e -> Printf.sprintf "(%S, %s)" (string_of_int i) e) fields
  in
  "`Assoc [" ^ String.concat "; " parts ^ "]"

let rec enc env recSet seen (t: Types.type_expr) : string =
  match Types.get_desc t with
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_int -> "(fun x -> `Int x)"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_bool -> "(fun x -> `Int (if x then 1 else 0))"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_string -> "(fun x -> `String x)"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_float -> "(fun x -> `Float x)"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_char -> "(fun x -> `Int (Char.code x))"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_unit -> "(fun _ -> `Int 0)"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_list ->
      "(fun xs -> let rec go = function [] -> `Int 0 | y :: ys -> "
      ^ block 0 [ "(" ^ enc env recSet seen a ^ ") y"; "go ys" ] ^ " in go xs)"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_option ->
      "(fun v -> match v with None -> `Int 0 | Some x -> "
      ^ block 0 [ "(" ^ enc env recSet seen a ^ ") x" ] ^ ")"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_array ->
      "(fun xs -> `List (Array.to_list (Array.map (" ^ enc env recSet seen a ^ ") xs)))"
  | Types.Tconstr (p, args, _) ->
      let n = typeName p in
      if List.mem n recSet then "toJson_" ^ n else encNamed env recSet seen n (Env.find_type p env) args
  | Types.Ttuple ts ->
      let ts = List.map snd ts in
      let vars = List.mapi (fun i _ -> Printf.sprintf "a%d" i) ts in
      let fields = List.map2 (fun v t -> "(" ^ enc env recSet seen t ^ ") " ^ v) vars ts in
      "(fun (" ^ String.concat ", " vars ^ ") -> " ^ block 0 fields ^ ")"
  | _ -> failwith "unsupported [@rpc] type (encoder)"

and encNamed env recSet seen name (d: Types.type_declaration) args =
  if List.mem name seen then failwith ("recursive [@rpc] type: " ^ name);
  let sub = withSub d args in
  match d.type_kind with
  | Types.Type_abstract _ ->
      (match d.type_manifest with
       | Some m -> enc env recSet seen (subst sub m)
       | None -> failwith ("unsupported abstract [@rpc] type: " ^ name))
  | Types.Type_record (labels, _) ->
      let fields =
        List.map
          (fun (l: Types.label_declaration) ->
            "(" ^ enc env recSet (name :: seen) (subst sub l.ld_type) ^ ") x." ^ Ident.name l.ld_id)
          labels
      in
      "(fun x -> " ^ block 0 fields ^ ")"
  | Types.Type_variant (ctors, _) ->
      let consts = List.filter isConstCtor ctors in
      let nonconsts = List.filter (fun c -> not (isConstCtor c)) ctors in
      let nc = List.length consts in
      let cases =
        ctors
        |> List.map (fun (c: Types.constructor_declaration) ->
               let cname = Ident.name c.cd_id in
               if isConstCtor c then Printf.sprintf "%s -> `Int %d" cname (indexOf c consts)
               else
                 let ts = List.map (subst sub) (Option.get (ctorArgs c)) in
                 let vars = List.mapi (fun i _ -> Printf.sprintf "v%d" i) ts in
                 let fields =
                   List.map2 (fun v t -> "(" ^ enc env recSet (name :: seen) t ^ ") " ^ v) vars ts
                 in
                 let pat = match vars with [ v ] -> v | vs -> "(" ^ String.concat ", " vs ^ ")" in
                 Printf.sprintf "%s %s -> %s" cname pat (block (nc + indexOf c nonconsts) fields))
      in
      "(fun x -> match x with " ^ String.concat " | " cases ^ ")"
  | _ -> failwith ("unsupported [@rpc] type: " ^ name)

let rec dec env recSet seen (t: Types.type_expr) : string =
  match Types.get_desc t with
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_int -> "Yojson.Safe.Util.to_int"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_bool -> "(fun j -> Yojson.Safe.Util.to_int j <> 0)"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_string -> "Yojson.Safe.Util.to_string"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_float -> "Yojson.Safe.Util.to_float"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_char -> "(fun j -> Char.chr (Yojson.Safe.Util.to_int j))"
  | Types.Tconstr (p, _, _) when Path.same p Predef.path_unit -> "(fun _ -> ())"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_list ->
      "(fun j -> let rec go j = match j with `Assoc o -> (" ^ dec env recSet seen a
      ^ ") (List.assoc \"0\" o) :: go (List.assoc \"1\" o) | _ -> [] in go j)"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_option ->
      "(fun j -> match j with `Assoc o -> Some ((" ^ dec env recSet seen a ^ ") (List.assoc \"0\" o)) | _ -> None)"
  | Types.Tconstr (p, [ a ], _) when Path.same p Predef.path_array ->
      "(fun j -> Array.of_list (List.map (" ^ dec env recSet seen a ^ ") (Yojson.Safe.Util.to_list j)))"
  | Types.Tconstr (p, args, _) ->
      let n = typeName p in
      if List.mem n recSet then "ofJson_" ^ n else decNamed env recSet seen n (Env.find_type p env) args
  | Types.Ttuple ts ->
      let ts = List.map snd ts in
      let fields =
        List.mapi (fun i t -> Printf.sprintf "(%s) (List.assoc %S o)" (dec env recSet seen t) (string_of_int i)) ts
      in
      "(fun j -> let o = Yojson.Safe.Util.to_assoc j in (" ^ String.concat ", " fields ^ "))"
  | _ -> failwith "unsupported [@rpc] type (decoder)"

and decNamed env recSet seen name (d: Types.type_declaration) args =
  if List.mem name seen then failwith ("recursive [@rpc] type: " ^ name);
  let sub = withSub d args in
  match d.type_kind with
  | Types.Type_abstract _ ->
      (match d.type_manifest with
       | Some m -> dec env recSet seen (subst sub m)
       | None -> failwith ("unsupported abstract [@rpc] type: " ^ name))
  | Types.Type_record (labels, _) ->
      let fields =
        List.mapi
          (fun i (l: Types.label_declaration) ->
            Printf.sprintf "%s = (%s) (List.assoc %S o)" (Ident.name l.ld_id)
              (dec env recSet (name :: seen) (subst sub l.ld_type)) (string_of_int i))
          labels
      in
      "(fun j -> let o = Yojson.Safe.Util.to_assoc j in { " ^ String.concat "; " fields ^ " })"
  | Types.Type_variant (ctors, _) ->
      let consts = List.filter isConstCtor ctors in
      let nonconsts = List.filter (fun c -> not (isConstCtor c)) ctors in
      let nc = List.length consts in
      let constCases =
        consts |> List.mapi (fun i (c: Types.constructor_declaration) -> Printf.sprintf "%d -> %s" i (Ident.name c.cd_id))
      in
      let nonconstCases =
        nonconsts
        |> List.mapi (fun i (c: Types.constructor_declaration) ->
               let ts = List.map (subst sub) (Option.get (ctorArgs c)) in
               let args =
                 List.mapi
                   (fun j t ->
                     Printf.sprintf "((%s) (List.assoc %S o))" (dec env recSet (name :: seen) t) (string_of_int j))
                   ts
               in
               let arg = match args with [ a ] -> a | _ -> "(" ^ String.concat ", " args ^ ")" in
               Printf.sprintf "%d -> %s %s" (nc + i) (Ident.name c.cd_id) arg)
      in
      "(fun j -> match j with `Int n -> (match n with " ^ String.concat " | " constCases
      ^ " | _ -> failwith \"bad variant\") | `Assoc o -> (match Yojson.Safe.Util.to_int (List.assoc \"$tag\" o) with "
      ^ String.concat " | " nonconstCases ^ " | _ -> failwith \"bad variant\") | _ -> failwith \"bad variant\")"
  | _ -> failwith ("unsupported [@rpc] type: " ^ name)

(* Collect the named record/variant types reachable from a set of types. *)
let collectTypes env (ts: Types.type_expr list) : (string * Types.type_declaration) list =
  let acc = Hashtbl.create 32 in
  let order = ref [] in
  let rec go t =
    match Types.get_desc t with
    | Types.Tconstr (p, args, _) ->
        List.iter go args;
        if unsupportedBoxed p then failwith ("unsupported [@rpc] type (boxed integer): " ^ Path.name p);
        if not (builtinPath p) then (
          let n = typeName p in
          if not (Hashtbl.mem acc n) then (
            let d = Env.find_type p env in
            Hashtbl.add acc n d;
            order := (n, d) :: !order;
            match d.type_kind with
            | Types.Type_record (ls, _) -> List.iter (fun (l: Types.label_declaration) -> go l.ld_type) ls
            | Types.Type_variant (cs, _) ->
                List.iter
                  (fun (c: Types.constructor_declaration) ->
                    match ctorArgs c with Some ts -> List.iter go ts | None -> ())
                  cs
            | Types.Type_abstract _ -> (match d.type_manifest with Some m -> go m | None -> ())
            | _ -> ()))
    | Types.Ttuple ts -> List.iter (fun (_, t) -> go t) ts
    | Types.Tarrow (_, a, b, _) -> go a; go b
    | _ -> ()
  in
  List.iter go ts;
  List.rev !order

let directRefNames (d: Types.type_declaration) : string list =
  let acc = ref [] in
  let rec go t =
    match Types.get_desc t with
    | Types.Tconstr (p, args, _) -> if builtinPath p then List.iter go args else acc := typeName p :: !acc
    | Types.Ttuple ts -> List.iter (fun (_, t) -> go t) ts
    | Types.Tarrow (_, a, b, _) -> go a; go b
    | _ -> ()
  in
  (match d.type_kind with
   | Types.Type_record (ls, _) -> List.iter (fun (l: Types.label_declaration) -> go l.ld_type) ls
   | Types.Type_variant (cs, _) ->
       List.iter (fun (c: Types.constructor_declaration) -> match ctorArgs c with Some ts -> List.iter go ts | None -> ()) cs
   | Types.Type_abstract _ -> (match d.type_manifest with Some m -> go m | None -> ())
   | _ -> ());
  !acc

(* Names of types that are part of a reference cycle. *)
let recursiveNames (collected: (string * Types.type_declaration) list) =
  let refs = collected |> List.map (fun (n, d) -> n, directRefNames d) in
  let lookup n = try List.assoc n refs with Not_found -> [] in
  let reaches start =
    let seen = Hashtbl.create 16 in
    let rec go n =
      if n = start then true
      else if Hashtbl.mem seen n then false
      else (Hashtbl.add seen n (); List.exists go (lookup n))
    in
    List.exists go (lookup start)
  in
  collected |> List.filter (fun (n, _) -> reaches n) |> List.map fst

(* `let rec` helper codecs for the recursive types. *)
let helperDefs env recSet (collected: (string * Types.type_declaration) list) : string =
  let ds = collected |> List.filter (fun (n, _) -> List.mem n recSet) in
  let defs =
    ds
    |> List.concat_map (fun ((n, d): string * Types.type_declaration) ->
           if d.type_params <> [] then failwith ("recursive generic [@rpc] type: " ^ n);
           [ "toJson_" ^ n ^ " = " ^ encNamed env recSet [] n d [];
             "ofJson_" ^ n ^ " = " ^ decNamed env recSet [] n d [] ])
  in
  match defs with
  | [] -> ""
  | first :: rest -> "let rec " ^ first ^ "\n" ^ String.concat "" (List.map (fun d -> "and " ^ d ^ "\n") rest)

let ofJson env recSet (t: Types.type_expr) = dec env recSet [] t
let toJson env recSet (t: Types.type_expr) = enc env recSet [] t

let rec arrows (t: Types.type_expr) : Types.type_expr list * Types.type_expr =
  match Types.get_desc t with
  | Types.Tarrow (_, a, b, _) ->
      let ps, r = arrows b in
      (a :: ps, r)
  | _ -> ([], t)

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
    (fun (a: Parsetree.attribute) -> a.attr_name.txt <> "javascript" && a.attr_name.txt <> "rpc")
    attrs

let openName (od: Parsetree.open_declaration) =
  match od.popen_expr.pmod_desc with
  | Parsetree.Pmod_ident { txt = lid; _ } ->
      (match List.rev (Longident.flatten lid) with
       | n :: _ -> Some n
       | [] -> None)
  | _ -> None

let serverItems (ast: Parsetree.structure) (js: string list) : Parsetree.structure =
  List.filter_map
    (fun (item: Parsetree.structure_item) ->
      match item.pstr_desc with
      (* Drop generated-binding opens (e.g. `open WebSharper_JavaScript`): the
         native server links our own `Async`, not the JS binding package. *)
      | Parsetree.Pstr_open od ->
          (match openName od with
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
    (js: string list) (rpcs: string list) =
  let files = typedTypes typed in
  let sigs =
    rpcs |> List.map (fun name ->
      let ps, ret = arrows (Hashtbl.find files name) in
      let ret = match asyncElem ret with Some inner -> inner | None -> ret in
      (name, ps, ret))
  in
  let collected = collectTypes env (List.concat_map (fun (_, ps, ret) -> ps @ [ ret ]) sigs) in
  let recSet = recursiveNames collected in
  let sb = Buffer.create 2048 in
  Buffer.add_string sb "(* Generated native RPC server. Do not edit. *)\n";
  Buffer.add_string sb (prettyStructure (serverItems ast js));
  Buffer.add_string sb "\n";
  Buffer.add_string sb (helperDefs env recSet collected);
  Buffer.add_string sb "let () =\n  let handlers = Hashtbl.create 16 in\n";
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
           "  Hashtbl.add handlers %S (fun (args : Yojson.Safe.t list) ->\n    match args with\n    | [ %s ] -> (%s) (%s)\n    | _ -> failwith \"rpc %s: wrong arity\");\n"
           name pattern (toJson env recSet ret) base name))
    sigs;
  Buffer.add_string sb "  Wsrpc.serve ~port:8123 handlers\n";
  let ch = open_out path in
  output_string ch (Buffer.contents sb);
  close_out ch

let () =
  let input = ref ""
  and output = ref ""
  and unit_name = ref ""
  and includes = ref []
  and emit_server = ref None in
  Arg.parse
    [
      ("--input", Arg.Set_string input, ".ml input");
      ("--output", Arg.Set_string output, "IR output");
      ("--unit", Arg.Set_string unit_name, "unit name");
      ("--emit-server", Arg.String (fun x -> emit_server := Some x), "emit a native RPC server .ml");
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
    checkBoundary ast;
    let js, rpc, srv = clientMarks ast in
    let typed, _, _, _, typedEnv = Typemod.type_structure env ast in
    (match !emit_server with
    | Some p ->
        emitServer p ast typed typedEnv js rpc;
        exit 0
    | None -> ());
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
          ("javascript", `List (List.map (fun n -> `String n) js));
          ("rpc", `List (List.map (fun n -> `String n) rpc));
          ("server", `List (List.map (fun n -> `String n) srv));
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
