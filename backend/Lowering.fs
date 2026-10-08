(*
 * WebSharper.OCaml: a strongly typed OCaml frontend for WebSharper.
 *
 * Copyright (c) 2026 IntelliFactory.
 * All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *)

namespace WebSharper.OCaml

open System.Collections.Generic
open WebSharper.Core.AST

module Lowering =
    type Ctx =
        {
            Vars: Dictionary<string, Id>
            Globals: Dictionary<string, Id>
            Current: string
            Runtime: bool ref
            Bindings: WebSharper.OCaml.Bindings.Context option
        }

    let id n = Id.New(n, false)
    let mutableId n = Id.New(n, true)
    let vid (i: Ident) = id i.Name
    let clone c = { c with Vars = Dictionary(c.Vars) }
    let prop o i = ItemGet(o, Value(Int i), Purity.Pure)

    let app f xs =
        Application(f, xs, ApplicationInfo.None)

    let rt (c: Ctx) name args =
        c.Runtime.Value <- true
        app (GlobalAccess(Address.LibAddr [ "OCamlRuntime"; name ])) args

    let rec lit c =
        function
        | LConst.I x -> Value(Int x)
        | LConst.F x -> Value(Double x)
        | LConst.S x -> Value(String x)
        | LConst.C x -> Value(Int(int x))
        | LConst.I32 x -> Value(Int(int x))
        | LConst.I64 x -> rt c "caml_int64_of_string" [ Value(String(string x)) ]
        | LConst.NI x -> rt c "caml_nativeint_of_string" [ Value(String(string x)) ]
        | LConst.Block(tag, xs) ->
            Object(
                ("$tag", MemberKind.Simple, Value(Int tag))
                :: (xs |> List.mapi (fun i x -> string i, MemberKind.Simple, lit c x))
            )
        | LConst.FloatArray xs -> NewTuple(xs |> List.map (fun x -> Value(Double x)), [])

    let getVar c n =
        match c.Vars.TryGetValue n with
        | true, v -> Var v
        | _ -> GlobalAccess(Address.LibAddr [ n ])

    let getGlobal c n =
        match c.Globals.TryGetValue n with
        | true, v -> Var v
        | _ ->
            let v = mutableId n
            c.Globals[n] <- v
            Var v

    let bin op a b = Binary(a, op, b)

    let cmp op a b =
        match op with
        | "eq" -> bin BinaryOperator.ReferenceEqualsOp a b
        | "ne" -> bin BinaryOperator.NotReferenceEquals a b
        | "lt" -> bin BinaryOperator.Less a b
        | "gt" -> bin BinaryOperator.Greater a b
        | "le" -> bin BinaryOperator.LessOrEquals a b
        | "ge" -> bin BinaryOperator.GreaterOrEquals a b
        | _ -> failwith $"unsupported comparison {op}"

    let exitTag = "$ocamlExit"
    let exitArgs = "$ocamlArgs"

    let splitOn (ch: char) (s: string) =
        match s.IndexOf ch with
        | -1 -> s, ""
        | i -> s.Substring(0, i), s.Substring(i + 1)

    let tryClass (c: Ctx) (asm: string) (addr: string) =
        c.Bindings |> Option.bind (fun ctx -> WebSharper.OCaml.Bindings.findClass ctx asm addr)

    let staticPayload tag args =
        Object
            [
                exitTag, MemberKind.Simple, Value(Int tag)
                exitArgs, MemberKind.Simple, NewTuple(args, [])
            ]

    let exitTagOf e =
        ItemGet(e, Value(String exitTag), Purity.Pure)

    let isStaticExit e tag =
        Binary(exitTagOf e, BinaryOperator.ReferenceEqualsOp, Value(Int tag))

    let isAnyStaticExit e =
        Binary(exitTagOf e, BinaryOperator.NotReferenceEquals, Undefined)

    let throw e = Throw e

    let rec expr c =
        function
        | LExpr.Var n -> getVar c n.Id
        | LExpr.Const k -> lit c k
        | LExpr.Fun(ps, b) ->
            let cc = clone c in

            let ids =
                ps
                |> List.map (fun p ->
                    let v = vid p in
                    cc.Vars[p.Id] <- v
                    v) in

            rt c "caml_closure" [ Value(Int(List.length ps)); Function(ids, None, None, Return(tailExpr cc b)) ]
        | LExpr.Apply(f, xs) -> rt c "caml_apply" [ expr c f; NewTuple(List.map (expr c) xs, []) ]
        | LExpr.Let(n, v, b) ->
            let cc = clone c in
            let x = vid n in
            cc.Vars[n.Id] <- x
            Let(x, expr c v, expr cc b)
        | LExpr.LetRec(bs, b) ->
            let cc = clone c in

            let ids =
                bs
                |> List.map (fun (n, _) ->
                    let x = vid n in
                    cc.Vars[n.Id] <- x
                    n, x) in

            LetRec(List.map2 (fun (_, x) (_, v) -> x, expr cc v) ids bs, expr cc b)
        | LExpr.If(a, b, d) -> Conditional(expr c a, expr c b, expr c d)
        | LExpr.Seq(a, b) ->
            Sequential[expr c a
                       expr c b]
        | LExpr.Assign(n, v) ->
            match c.Vars.TryGetValue n.Id with
            | true, x -> VarSet(x, expr c v)
            | _ -> failwith $"assignment to unknown {n.Name}"
        | LExpr.While(a, b) -> StatementExpr(While(expr c a, ExprStatement(expr c b)), None)
        | LExpr.For(n, a, b, down, body) ->
            let cc = clone c in
            let x = vid n in
            cc.Vars[n.Id] <- x
            let init = VarDeclaration(x, expr c a)

            let test =
                Binary(
                    Var x,
                    (if down then
                         BinaryOperator.GreaterOrEquals
                     else
                         BinaryOperator.LessOrEquals),
                    expr c b
                )

            let step =
                VarSet(
                    x,
                    Binary(
                        Var x,
                        (if down then
                             BinaryOperator.Substract
                         else
                             BinaryOperator.Add),
                        Value(Int 1)
                    )
                )

            StatementExpr(
                Block[init

                      While(
                          test,
                          Block[ExprStatement(expr cc body)
                                ExprStatement step]
                      )],
                None
            )
        | LExpr.Prim(p, xs) -> prim c p xs
        | LExpr.Switch(x, cs, bs, fail) -> switch c false (expr c x) cs bs fail
        | LExpr.StringSwitch(x, cs, fail) -> switchString c false (expr c x) cs fail
        | LExpr.StaticRaise(tag, xs) -> StatementExpr(Throw(staticPayload tag (List.map (expr c) xs)), None)
        | LExpr.StaticCatch(body, tag, ps, handler) ->
            let result = id "exitResult"
            let exn = id "exitValue"
            let cc = clone c

            let binds =
                ps
                |> List.mapi (fun i p ->
                    let v = vid p in
                    cc.Vars[p.Id] <- v

                    VarDeclaration(
                        v,
                        ItemGet(ItemGet(Var exn, Value(String exitArgs), Purity.Pure), Value(Int i), Purity.Pure)
                    ))

            let catchStmt =
                If(
                    isStaticExit (Var exn) tag,
                    Block(binds @ [ ExprStatement(VarSet(result, expr cc handler)) ]),
                    throw (Var exn)
                )

            StatementExpr(TryWith(ExprStatement(VarSet(result, expr c body)), Some exn, catchStmt), Some result)
        | LExpr.TryWith(body, exnIdent, handler) ->
            let result = id "tryResult"
            let exn = id "tryValue"
            let cc = clone c
            cc.Vars[exnIdent.Id] <- exn

            let catchStmt =
                If(isAnyStaticExit (Var exn), throw (Var exn), ExprStatement(VarSet(result, expr cc handler)))

            StatementExpr(TryWith(ExprStatement(VarSet(result, expr c body)), Some exn, catchStmt), Some result)

    and tailExpr c e =
        match e with
        | LExpr.Apply(f, xs) -> rt c "caml_trampoline_return" [ expr c f; NewTuple(List.map (expr c) xs, []) ]
        | LExpr.If(a, b, d) -> Conditional(expr c a, tailExpr c b, tailExpr c d)
        | LExpr.Seq(a, b) -> Sequential[ expr c a; tailExpr c b ]
        | LExpr.Let(n, v, b) ->
            let cc = clone c
            let x = vid n
            cc.Vars[n.Id] <- x
            Expression.Let(x, expr c v, tailExpr cc b)
        | LExpr.LetRec(bs, b) ->
            let cc = clone c

            let ids =
                bs
                |> List.map (fun (n, _) ->
                    let x = vid n in
                    cc.Vars[n.Id] <- x
                    n, x)

            LetRec(List.map2 (fun (_, x) (_, v) -> x, expr cc v) ids bs, tailExpr cc b)
        | LExpr.Switch(x, cs, bs, fail) -> switch c true (expr c x) cs bs fail
        | LExpr.StringSwitch(x, cs, fail) -> switchString c true (expr c x) cs fail
        | _ -> expr c e

    and prim c p xs =
        let es = List.map (expr c) xs

        match p.Tag, es with
        | "ignore", [ x ] ->
            Sequential[x
                       Undefined]
        | "getglobal", [] -> getGlobal c p.Name.Value
        | "setglobal", [ v ] ->
            let g = getGlobal c p.Name.Value in

            match g with
            | Var x -> VarSet(x, v)
            | _ -> failwith "internal global"
        | "makeblock", _ ->
            Object(
                ("$tag", MemberKind.Simple, Value(Int p.BlockTag.Value))
                :: (es |> List.mapi (fun i x -> string i, MemberKind.Simple, x))
            )
        | "field", [ x ] -> prop x p.Index.Value
        | "setfield", [ x; v ] -> ItemSet(x, Value(Int p.Index.Value), v)
        | "field_computed", [ x; i ] -> ItemGet(x, i, Purity.Pure)
        | "setfield_computed", [ x; i; v ] -> ItemSet(x, i, v)
        | "addint", [ a; b ]
        | "addfloat", [ a; b ] -> bin BinaryOperator.Add a b
        | "subint", [ a; b ]
        | "subfloat", [ a; b ] -> bin BinaryOperator.Substract a b
        | "mulint", [ a; b ]
        | "mulfloat", [ a; b ] -> bin BinaryOperator.Multiply a b
        | "divfloat", [ a; b ] -> bin BinaryOperator.Divide a b
        | "divint", [ a; b ] -> rt c "caml_div" [ a; b ]
        | "modint", [ a; b ] -> rt c "caml_mod" [ a; b ]
        | "and", [ a; b ] -> bin BinaryOperator.And a b
        | "or", [ a; b ] -> bin BinaryOperator.Or a b
        | "bitand", [ a; b ] -> bin BinaryOperator.BitwiseAnd a b
        | "bitor", [ a; b ] -> bin BinaryOperator.BitwiseOr a b
        | "bitxor", [ a; b ] -> bin BinaryOperator.BitwiseXor a b
        | "lsl", [ a; b ] -> bin BinaryOperator.LeftShift a b
        | "lsr", [ a; b ] -> bin BinaryOperator.UnsignedRightShift a b
        | "asr", [ a; b ] -> bin BinaryOperator.RightShift a b
        | "bytes_to_string", [ a ] -> rt c "caml_bytes_to_string" [ a ]
        | "bytes_of_string", [ a ] -> rt c "caml_bytes_of_string" [ a ]
        | "isint", [ a ] -> rt c "caml_is_int" [ a ]
        | "isout", [ i; a ] -> rt c "caml_is_out" [ i; a ]
        | "intcompare", [ a; b ] -> rt c "caml_compare_ints" [ a; b ]
        | "compare_floats", [ a; b ] -> rt c "caml_compare_floats" [ a; b ]
        | "dup_array", [ a ] -> rt c "caml_dup_array" [ a ]
        | "bintofint", [ a ] -> rt c "caml_bint_of_int" [ Value(String p.Kind.Value); a ]
        | "intofbint", [ a ] -> rt c "caml_int_of_bint" [ Value(String p.Kind.Value); a ]
        | "negbint", [ a ] -> rt c "caml_bint_neg" [ Value(String p.Kind.Value); a ]
        | "addbint", [ a; b ] -> rt c "caml_bint_add" [ Value(String p.Kind.Value); a; b ]
        | "subbint", [ a; b ] -> rt c "caml_bint_sub" [ Value(String p.Kind.Value); a; b ]
        | "mulbint", [ a; b ] -> rt c "caml_bint_mul" [ Value(String p.Kind.Value); a; b ]
        | "andbint", [ a; b ] -> rt c "caml_bint_and" [ Value(String p.Kind.Value); a; b ]
        | "orbint", [ a; b ] -> rt c "caml_bint_or" [ Value(String p.Kind.Value); a; b ]
        | "xorbint", [ a; b ] -> rt c "caml_bint_xor" [ Value(String p.Kind.Value); a; b ]
        | "lslbint", [ a; b ] -> rt c "caml_bint_lsl" [ Value(String p.Kind.Value); a; b ]
        | "lsrbint", [ a; b ] -> rt c "caml_bint_lsr" [ Value(String p.Kind.Value); a; b ]
        | "asrbint", [ a; b ] -> rt c "caml_bint_asr" [ Value(String p.Kind.Value); a; b ]
        | "divbint", [ a; b ] -> rt c "caml_bint_div" [ Value(String p.Kind.Value); a; b ]
        | "modbint", [ a; b ] -> rt c "caml_bint_mod" [ Value(String p.Kind.Value); a; b ]
        | "bintcomp", [ a; b ] -> rt c "caml_bint_comp" [ Value(String p.Kind.Value); Value(String p.Op.Value); a; b ]
        | "compare_bints", [ a; b ] -> rt c "caml_bint_compare" [ Value(String p.Kind.Value); a; b ]
        | "cvtbint", [ a ] -> rt c "caml_bint_conv" [ Value(String p.Src.Value); Value(String p.Kind.Value); a ]
        | "bbswap", [ a ] -> rt c "caml_bint_bswap" [ Value(String p.Kind.Value); a ]
        | "bytes_set16", [ b; i; v ] -> rt c "caml_bytes_set16" [ b; i; v ]
        | "bytes_set32", [ b; i; v ] -> rt c "caml_bytes_set32" [ b; i; v ]
        | "bytes_set64", [ b; i; v ] -> rt c "caml_bytes_set64" [ b; i; v ]
        | "bytes_get16", [ b; i ] -> rt c "caml_bytes_get16" [ b; i ]
        | "bytes_get32", [ b; i ] -> rt c "caml_bytes_get32" [ b; i ]
        | "bytes_get64", [ b; i ] -> rt c "caml_bytes_get64" [ b; i ]
        | "ctconst", _ -> Value(Int p.Value.Value)
        | "bswap16", [ a ] -> rt c "caml_bswap16" [ a ]
        | "identity", [ a ] -> a
        | "makelazy", [ f ] -> rt c "caml_lazy_make" [ f ]
        | "makeforward", [ v ] -> rt c "caml_lazy_make_forward" [ v ]
        | "atomic_load", [ r; _ ] -> rt c "caml_atomic_load" [ r ]
        | "not", [ a ] -> Unary(UnaryOperator.Not, a)
        | "negint", [ a ]
        | "negfloat", [ a ] -> Unary(UnaryOperator.Inversion, a)
        | "intcomp", [ a; b ]
        | "floatcomp", [ a; b ] -> cmp p.Op.Value a b
        | "offsetint", [ a ] -> bin BinaryOperator.Add a (Value(Int p.Value.Value))
        | "offsetref", [ r ] ->
            Sequential
                [ ItemSet(r, Value(Int 0), Binary(prop r 0, BinaryOperator.Add, Value(Int p.Value.Value)))
                  Undefined ]
        | "makearray", _ -> NewTuple(es, [])
        | "arraylength", [ a ]
        | "stringlength", [ a ]
        | "byteslength", [ a ] -> ItemGet(a, Value(String "length"), Purity.Pure)
        | "arrayref", [ a; i ]
        | "bytesref", [ a; i ] -> ItemGet(a, i, Purity.Pure)
        | "stringref", [ a; i ] -> rt c "caml_string_unsafe_get" [ a; i ]
        | "arrayset", [ a; i; v ]
        | "bytesset", [ a; i; v ] -> ItemSet(a, i, v)
        | "opaque", [ a ] -> a
        | "poll", [] -> Undefined
        | "raise", [ x ] -> StatementExpr(Throw x, None)
        | "ccall", _ ->
            let name = p.Name.Value
            let parts () = (name.Substring(name.IndexOf(':') + 1)).Split '.' |> Array.toList

            let globalAddr () = GlobalAccess(Address.LibAddr(parts ()))

            if name.StartsWith "jsnew0:" then
                New(GlobalAccess(Address.LibAddr(parts ())), [], [])
            elif name.StartsWith "jsnew:" then
                New(globalAddr (), [], es)
            elif name.StartsWith "js0:" then
                app (globalAddr ()) []
            elif name.StartsWith "jsget:" then
                match parts () with
                | [ single ] -> GlobalAccess(Address.LibAddr [ single ])
                | ps ->
                    let obj, prop =
                        match List.rev ps with
                        | p :: rest -> List.rev rest, p
                        | [] -> [], ""

                    ItemGet(GlobalAccess(Address.LibAddr obj), Value(String prop), Purity.Pure)
            elif name = "jsdget" then
                match es with
                | [ o; k ] -> ItemGet(o, k, Purity.Pure)
                | _ -> failwith "jsdget: expects object and key"
            elif name = "jsdset" then
                match es with
                | [ o; k; v ] -> ItemSet(o, k, v)
                | _ -> failwith "jsdset: expects object, key and value"
            elif name.StartsWith "jsset:" then
                let ps = parts () in

                let obj, prop =
                    match List.rev ps with
                    | p :: rest -> List.rev rest, p
                    | [] -> [], ""

                match es with
                | [ v ] -> ItemSet(GlobalAccess(Address.LibAddr obj), Value(String prop), v)
                | _ -> failwith "jsset expects one argument"
            elif name.StartsWith "jse:" then
                match es with
                | recv :: rest ->
                    app
                        (ItemGet(recv, Value(String "addEventListener"), Purity.Pure))
                        (Value(String(name.Substring 4)) :: rest)
                | [] -> failwith "jse: expects a receiver and a listener"
            elif name.StartsWith "jsm:" then
                match es with
                | recv :: rest -> app (ItemGet(recv, Value(String(name.Substring 4)), Purity.Pure)) rest
                | [] -> failwith "jsm: expects a receiver"
            elif name.StartsWith "jsgp:" then
                match es with
                | [ recv ] -> ItemGet(recv, Value(String(name.Substring 5)), Purity.Pure)
                | _ -> failwith "jsgp: expects a receiver"
            elif name.StartsWith "jssp:" then
                match es with
                | [ recv; v ] -> ItemSet(recv, Value(String(name.Substring 5)), v)
                | _ -> failwith "jssp: expects receiver and value"
            elif name.StartsWith "js:" then
                app (globalAddr ()) es
            elif name.StartsWith "wsnew:" then
                let asm, addr = splitOn '!' (name.Substring 6)
                match tryClass c asm addr with
                | Some e -> New(GlobalAccess e.Address, [], es)
                | None -> failwith $"wsnew: unknown class {addr}"
            elif name.StartsWith "wsget:" then
                let qual, field = splitOn '#' (name.Substring 6)
                let asm, addr = splitOn '!' qual
                match tryClass c asm addr with
                | Some e ->
                    match WebSharper.OCaml.Bindings.findField e.Class field with
                    | Some f ->
                        if f.CompiledForm.IsStaticField then
                            ItemGet(GlobalAccess e.Address, Value(String field), Purity.Pure)
                        else
                            match es with
                            | [ recv ] -> ItemGet(recv, Value(String field), Purity.Pure)
                            | _ -> failwith "wsget: expects a receiver"
                    | None -> failwith $"wsget: unknown field {field}"
                | None -> failwith $"wsget: unknown class {addr}"
            elif name.StartsWith "wsset:" then
                let qual, field = splitOn '#' (name.Substring 6)
                let asm, addr = splitOn '!' qual
                match tryClass c asm addr with
                | Some e ->
                    match WebSharper.OCaml.Bindings.findField e.Class field with
                    | Some f ->
                        if f.CompiledForm.IsStaticField then
                            match es with
                            | [ v ] -> ItemSet(GlobalAccess e.Address, Value(String field), v)
                            | _ -> failwith "wsset: expects a value"
                        else
                            match es with
                            | [ recv; v ] -> ItemSet(recv, Value(String field), v)
                            | _ -> failwith "wsset: expects a receiver and a value"
                    | None -> failwith $"wsset: unknown field {field}"
                | None -> failwith $"wsset: unknown class {addr}"
            elif name.StartsWith "ws:" then
                let parts = (name.Substring 3).Split('|')
                let qual, mn = splitOn '#' parts.[0]
                let ps = parts.[1..] |> Array.toList |> List.filter (fun s -> s <> "")
                let asm, addr = splitOn '!' qual
                match tryClass c asm addr with
                | Some e ->
                    match WebSharper.OCaml.Bindings.findMethod e.Class mn ps with
                    | Some(mi, cmi) ->
                        let form = cmi.CompiledForm
                        if form.IsMacro then
                            failwith $"ws: '{mn}' is a WebSharper macro; macros are not supported"
                        elif form.IsNew then
                            New(GlobalAccess e.Address, [], es)
                        elif form.IsInline then
                            WebSharper.OCaml.Bindings.substituteHoles es cmi.Expression
                        elif WebSharper.OCaml.Bindings.hasBody cmi.Expression then
                            // Compiled (Static/Func/Instance) body stored in metadata:
                            // inline it (hole-based) or apply the function value.
                            if WebSharper.OCaml.Bindings.maxHole cmi.Expression >= 0 then
                                WebSharper.OCaml.Bindings.substituteHoles es cmi.Expression
                            else
                                app cmi.Expression es
                        elif form.IsInstance then
                            match es with
                            | recv :: rest ->
                                app (ItemGet(recv, Value(String(WebSharper.OCaml.Bindings.methodJsName mi)), Purity.Pure)) rest
                            | [] -> failwith "ws: instance method expects a receiver"
                        else
                            app (ItemGet(GlobalAccess e.Address, Value(String(WebSharper.OCaml.Bindings.methodJsName mi)), Purity.Pure)) es
                    | None -> failwith $"ws: unknown member {mn}"
                | None -> failwith $"ws: unknown class {addr}"
            else
                rt c name es
        | tag, _ -> failwith $"Lambda primitive '{tag}' is not lowered yet"

    and switch c tail x cs bs fail =
        let xv: Expression = x
        let tag: Expression = ItemGet(xv, Value(String "$tag"), Purity.Pure)
        let body = if tail then tailExpr else expr

        let cases: (Expression * LExpr) list =
            (cs
             |> List.map (fun (k, b) -> Binary(xv, BinaryOperator.ReferenceEqualsOp, Value(Int k)), b))
            @ (bs
               |> List.map (fun (k, b) -> Binary(tag, BinaryOperator.ReferenceEqualsOp, Value(Int k)), b))

        let fallback: Expression =
            match fail with
            | Some z -> expr c z
            | None -> Undefined

        List.foldBack (fun (test, b) acc -> Conditional(test, body c b, acc)) cases fallback

    and switchString c tail x cs fail =
        let xv: Expression = x
        let body = if tail then tailExpr else expr

        let cases: (Expression * LExpr) list =
            cs
            |> List.map (fun (k, b) -> Binary(xv, BinaryOperator.ReferenceEqualsOp, Value(String k)), b)

        let fallback: Expression =
            match fail with
            | Some z -> expr c z
            | None -> Undefined

        List.foldBack (fun (test, b) acc -> Conditional(test, body c b, acc)) cases fallback

    let compile (bindings: WebSharper.OCaml.Bindings.Context option) (ir: UnitIR) =
        let gs = Dictionary<string, Id>()
        let runtime = ref false

        let c =
            {
                Vars = Dictionary()
                Globals = gs
                Current = ir.ModuleIdent
                Runtime = runtime
                Bindings = bindings
            }

        let imports =
            ir.RequiredGlobals
            |> List.filter ((<>) ir.ModuleIdent)
            |> List.map (fun n ->
                let v = id n in
                gs[n] <- v
                Import(Some v, None, [], "./" + n + ".js"))

        let me = mutableId ir.ModuleIdent in
        gs[ir.ModuleIdent] <- me
        let init = VarDeclaration(me, Object [])
        let body = ExprStatement(expr c ir.Code)
        let export = ExportDecl(true, ExprStatement(Var me))
        imports @ [ init; body; export ], runtime.Value
