(*
 * WebSharper.OCaml: a strongly typed OCaml frontend for WebSharper.
 *
 * Copyright (c) 2026 IntelliFactory.
 * All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *)

namespace WebSharper.OCaml

open System
open System.IO
open System.Reflection
open WebSharper.Core
open WebSharper.Core.AST
open WebSharper.Core.Metadata

module Bindings =

    type Entry =
        { Assembly: string
          Address: Address
          Class: ClassInfo }

    type Context = { Entries: Entry list }

    let private lowerFirst (s: string) =
        if String.IsNullOrEmpty s then s
        else string (Char.ToLower s.[0]) + s.Substring(1)

    let rec typeDisplay (t: Type) : string =
        match t with
        | Type.VoidType -> "void"
        | Type.ConcreteType c ->
            let generics = c.Generics |> List.map typeDisplay
            match generics with
            | [] -> c.Entity.Value.FullName
            | gs -> c.Entity.Value.FullName + "<" + String.concat "," gs + ">"
        | Type.TypeParameter i -> "'" + string i
        | Type.ArrayType(e, rank) -> typeDisplay e + String.replicate rank "[]"
        | Type.TupleType(ts, _) -> "(" + String.concat "," (ts |> List.map typeDisplay) + ")"
        | Type.FSharpFuncType _ -> "fn"
        | Type.ByRefType u -> typeDisplay u
        | _ -> "?"

    let load (paths: string list) : Context =
        let entries =
            paths
            |> List.collect (fun path ->
                let asm = Assembly.LoadFrom(Path.GetFullPath path)
                let name = Path.GetFileNameWithoutExtension path
                match IO.LoadMetadata asm with
                | None -> []
                | Some info ->
                    info.Classes
                    |> Seq.choose (fun kv ->
                        let (a, _custom, ci) = kv.Value
                        match ci with
                        | Some ci -> Some { Assembly = name; Address = a; Class = ci }
                        | None -> None)
                    |> Seq.toList)
        { Entries = entries }

    let findClass (ctx: Context) (asm: string) (addr: string) =
        let matches (e: Entry) = e.Address.ToString() = addr
        ctx.Entries
        |> List.tryFind (fun e -> matches e && e.Assembly = asm)
        |> Option.orElseWith (fun () -> ctx.Entries |> List.tryFind matches)

    let findMethod (ci: ClassInfo) (name: string) (paramDisplays: string list) =
        ci.Methods
        |> Seq.tryPick (fun kv ->
            let mi = kv.Key.Value
            let ps = mi.Parameters |> List.map typeDisplay
            if mi.MethodName = name && ps = paramDisplays then Some(mi, kv.Value) else None)

    let findField (ci: ClassInfo) (name: string) =
        match ci.Fields.TryGetValue name with
        | true, f -> Some f
        | _ -> None

    let methodJsName (mi: MethodInfo) = lowerFirst mi.MethodName

    type private HoleSubstitution(holes: Expression list) =
        inherit Transformer()
        override this.TransformHole(i: int) =
            if i >= 0 && i < holes.Length then holes.[i] else Undefined

    let substituteHoles (holes: Expression list) (body: Expression) =
        let t = HoleSubstitution(holes)
        t.TransformExpression body
