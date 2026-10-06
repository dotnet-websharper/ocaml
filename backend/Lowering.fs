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
        }

    let id n = Id.New(n, false)
    let mutableId n = Id.New(n, true)
    let vid (i: Ident) = id i.Name
    let clone c = { c with Vars = Dictionary(c.Vars) }
    let prop o i = ItemGet(o, Value(Int i), Purity.Pure)

    let app f xs =
        Application(f, xs, ApplicationInfo.None)

    let rec lit =
        function
        | LConst.I x -> Value(Int x)
        | LConst.F x -> Value(Double x)
        | LConst.S x -> Value(String x)
        | LConst.C x -> Value(Char x)
        | LConst.I32 x -> Value(Int(int x))
        | LConst.I64 x -> Value(Double(float x))
        | LConst.NI x -> Value(Double(float x))
        | LConst.Block(tag, xs) ->
            Object(
                ("$tag", MemberKind.Simple, Value(Int tag))
                :: (xs |> List.mapi (fun i x -> string i, MemberKind.Simple, lit x))
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
        | LExpr.Const k -> lit k
        | LExpr.Fun(ps, b) ->
            let cc = clone c in

            let ids =
                ps
                |> List.map (fun p ->
                    let v = vid p in
                    cc.Vars[p.Id] <- v
                    v) in

            Function(ids, None, None, Return(expr cc b))
        | LExpr.Apply(f, xs) -> app (expr c f) (List.map (expr c) xs)
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
        | LExpr.Switch(x, cs, bs, fail) -> switch c (expr c x) cs bs fail
        | LExpr.StringSwitch(x, cs, fail) -> switchString c (expr c x) cs fail
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
        | "divint", [ a; b ]
        | "divfloat", [ a; b ] -> bin BinaryOperator.Divide a b
        | "modint", [ a; b ] -> bin BinaryOperator.Modulo a b
        | "and", [ a; b ] -> bin BinaryOperator.And a b
        | "or", [ a; b ] -> bin BinaryOperator.Or a b
        | "not", [ a ] -> Unary(UnaryOperator.Not, a)
        | "negint", [ a ]
        | "negfloat", [ a ] -> Unary(UnaryOperator.Inversion, a)
        | "intcomp", [ a; b ]
        | "floatcomp", [ a; b ] -> cmp p.Op.Value a b
        | "offsetint", [ a ] -> bin BinaryOperator.Add a (Value(Int p.Value.Value))
        | "makearray", _ -> NewTuple(es, [])
        | "arraylength", [ a ]
        | "stringlength", [ a ]
        | "byteslength", [ a ] -> ItemGet(a, Value(String "length"), Purity.Pure)
        | "arrayref", [ a; i ]
        | "stringref", [ a; i ]
        | "bytesref", [ a; i ] -> ItemGet(a, i, Purity.Pure)
        | "arrayset", [ a; i; v ]
        | "bytesset", [ a; i; v ] -> ItemSet(a, i, v)
        | "opaque", [ a ] -> a
        | "poll", [] -> Undefined
        | "raise", [ x ] -> StatementExpr(Throw x, None)
        | "ccall", _ ->
            c.Runtime.Value <- true
            app (GlobalAccess(Address.LibAddr [ "OCamlRuntime"; p.Name.Value ])) es
        | tag, _ -> failwith $"Lambda primitive '{tag}' is not lowered yet"

    and switch c x cs bs fail =
        let xv: Expression = x
        let tag: Expression = ItemGet(xv, Value(String "$tag"), Purity.Pure)

        let cases: (Expression * LExpr) list =
            (cs
             |> List.map (fun (k, b) -> Binary(xv, BinaryOperator.ReferenceEqualsOp, Value(Int k)), b))
            @ (bs
               |> List.map (fun (k, b) -> Binary(tag, BinaryOperator.ReferenceEqualsOp, Value(Int k)), b))

        let fallback: Expression =
            match fail with
            | Some z -> expr c z
            | None -> Undefined

        List.foldBack (fun (test, b) acc -> Conditional(test, expr c b, acc)) cases fallback

    and switchString c x cs fail =
        let xv: Expression = x

        let cases: (Expression * LExpr) list =
            cs
            |> List.map (fun (k, b) -> Binary(xv, BinaryOperator.ReferenceEqualsOp, Value(String k)), b)

        let fallback: Expression =
            match fail with
            | Some z -> expr c z
            | None -> Undefined

        List.foldBack (fun (test, b) acc -> Conditional(test, expr c b, acc)) cases fallback

    let compile (ir: UnitIR) =
        let gs = Dictionary<string, Id>()
        let runtime = ref false

        let c =
            {
                Vars = Dictionary()
                Globals = gs
                Current = ir.ModuleIdent
                Runtime = runtime
            }

        let imports =
            ir.RequiredGlobals
            |> List.filter ((<>) ir.ModuleIdent)
            |> List.map (fun n ->
                let v = id n in
                gs[n] <- v
                Import(None, Some v, [], "./" + n + ".js"))

        let me = mutableId ir.ModuleIdent in
        gs[ir.ModuleIdent] <- me
        let init = VarDeclaration(me, Undefined)
        let body = ExprStatement(expr c ir.Code)
        let export = ExportDecl(true, ExprStatement(Var me))
        imports @ [ init; body; export ], runtime.Value
