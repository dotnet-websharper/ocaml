(*
 * WebSharper.OCaml: a strongly typed OCaml frontend for WebSharper.
 *
 * Copyright (c) 2026 IntelliFactory.
 * All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *)

namespace WebSharper.OCaml

open System.Text.Json

type LConst =
    | I of int
    | F of float
    | S of string
    | C of char
    | I32 of int32
    | I64 of int64
    | NI of int64
    | Block of int * LConst list
    | FloatArray of float list

type Ident = { Id: string; Name: string }

type Prim =
    {
        Tag: string
        Name: string option
        Index: int option
        BlockTag: int option
        Op: string option
        Kind: string option
        Mutable: bool option
        Value: int option
        Safe: bool option
    }

type LExpr =
    | Var of Ident
    | Const of LConst
    | Fun of Ident list * LExpr
    | Apply of LExpr * LExpr list
    | Let of Ident * LExpr * LExpr
    | LetRec of (Ident * LExpr) list * LExpr
    | Prim of Prim * LExpr list
    | Switch of LExpr * (int * LExpr) list * (int * LExpr) list * LExpr option
    | StringSwitch of LExpr * (string * LExpr) list * LExpr option
    | If of LExpr * LExpr * LExpr
    | Seq of LExpr * LExpr
    | While of LExpr * LExpr
    | For of Ident * LExpr * LExpr * bool * LExpr
    | Assign of Ident * LExpr
    | StaticRaise of int * LExpr list
    | StaticCatch of LExpr * int * Ident list * LExpr
    | TryWith of LExpr * Ident * LExpr

type UnitIR =
    {
        Schema: string
        Unit: string
        ModuleIdent: string
        MainModuleBlockSize: int
        RequiredGlobals: string list
        Code: LExpr
    }

module Json =
    let private p (n:string) (e: JsonElement) = e.GetProperty n
    let private s (n:string) e = (p n e).GetString()
    let private a (n:string) (e: JsonElement) : JsonElement list = p n e |> fun x -> [ for i in x.EnumerateArray() -> i ]

    let private ident (e: JsonElement) : Ident =
        { Id = s "id" e; Name = s "name" e }

    let private optProp (n:string) (e: JsonElement) =
        match e.TryGetProperty n with
        | true, x -> Some x
        | _ -> None

    let private nullable f (e: JsonElement) =
        if e.ValueKind = JsonValueKind.Null then None else Some(f e)

    let rec private c (e: JsonElement) =
        match s "tag" e with
        | "int" -> I(int (s "value" e))
        | "float" -> F(float (s "value" e))
        | "string" -> S(s "value" e)
        | "char" -> C((s "value" e).[0])
        | "int32" -> I32(int32 (s "value" e))
        | "int64" -> I64(int64 (s "value" e))
        | "nativeint" -> NI(int64 (s "value" e))
        | "block" -> Block((p "blockTag" e).GetInt32(), a "items" e |> List.map c)
        | "float_array" -> FloatArray(a "items" e |> List.map (fun x -> float (x.GetString())))
        | x -> failwith $"unknown constant {x}"

    let private prim (e: JsonElement) =
        let oi n =
            optProp n e |> Option.map (fun x -> x.GetInt32())

        let os n =
            optProp n e |> Option.map (fun x -> x.GetString())

        let ob n =
            optProp n e |> Option.map (fun x -> x.GetBoolean())

        {
            Tag = s "tag" e
            Name = os "name"
            Index = oi "index"
            BlockTag = oi "blockTag"
            Op = os "op"
            Kind = os "kind"
            Mutable = ob "mutable"
            Value = oi "value"
            Safe = ob "safe"
        }

    let rec private expr (e: JsonElement) =
        match s "tag" e with
        | "var" -> Var(ident (p "var" e))
        | "const" -> Const(c (p "value" e))
        | "fun" -> Fun(a "params" e |> List.map ident, expr (p "body" e))
        | "apply" -> Apply(expr (p "func" e), a "args" e |> List.map expr)
        | "let" -> Let(ident (p "var" e), expr (p "value" e), expr (p "body" e))
        | "letrec" -> LetRec(a "bindings" e |> List.map (fun x -> ident (p "var" x), expr (p "value" x)), expr (p "body" e))
        | "prim" -> Prim(prim (p "prim" e), a "args" e |> List.map expr)
        | "if" -> If(expr (p "cond" e), expr (p "then" e), expr (p "else" e))
        | "seq" -> Seq(expr (p "first" e), expr (p "second" e))
        | "while" -> While(expr (p "cond" e), expr (p "body" e))
        | "for" -> For(ident (p "var" e), expr (p "from" e), expr (p "to" e), (p "down" e).GetBoolean(), expr (p "body" e))
        | "assign" -> Assign(ident (p "var" e), expr (p "value" e))
        | "switch" ->
            Switch(
                expr (p "expr" e),
                a "consts" e |> List.map (fun x -> (p "key" x).GetInt32(), expr (p "body" x)),
                a "blocks" e |> List.map (fun x -> (p "key" x).GetInt32(), expr (p "body" x)),
                nullable expr (p "fail" e)
            )
        | "stringswitch" ->
            StringSwitch(
                expr (p "expr" e),
                a "cases" e |> List.map (fun x -> s "key" x, expr (p "body" x)),
                nullable expr (p "fail" e)
            )
        | "staticraise" -> StaticRaise((p "id" e).GetInt32(), a "args" e |> List.map expr)
        | "staticcatch" ->
            StaticCatch(
                expr (p "body" e),
                (p "id" e).GetInt32(),
                a "params" e |> List.map ident,
                expr (p "handler" e)
            )
        | "trywith" -> TryWith(expr (p "body" e), ident (p "var" e), expr (p "handler" e))
        | x -> failwith $"unknown lambda node {x}"

    let read path =
        use d = JsonDocument.Parse(System.IO.File.ReadAllText path)
        let r = d.RootElement

        {
            Schema = s "schema" r
            Unit = s "unit" r
            ModuleIdent = s "moduleIdent" r
            MainModuleBlockSize = (p "mainModuleBlockSize" r).GetInt32()
            RequiredGlobals = a "requiredGlobals" r |> List.map (fun x -> x.GetString())
            Code = expr (p "code" r)
        }
