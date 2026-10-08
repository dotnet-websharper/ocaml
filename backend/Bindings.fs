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
          Class: ClassInfo
          TypeKey: Hashed<TypeDefinitionInfo> }

    type Context =
        { Entries: Entry list
          RefMeta: Info
          Comp: WebSharper.Compiler.Compilation }

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
        let metadatas =
            paths
            |> List.map (fun path ->
                let asm = Assembly.LoadFrom(Path.GetFullPath path)
                Path.GetFileNameWithoutExtension path, IO.LoadMetadata asm)

        let infos = metadatas |> List.choose snd

        let refMeta =
            if infos.IsEmpty then Info.Empty
            else Info.UnionWithoutDependencies infos

        let entries =
            metadatas
            |> List.collect (fun (name, m) ->
                match m with
                | None -> []
                | Some info ->
                    info.Classes
                    |> Seq.choose (fun kv ->
                        let (a, _custom, ci) = kv.Value
                        match ci with
                        | Some ci ->
                            Some
                                { Assembly = name
                                  Address = a
                                  Class = ci
                                  TypeKey = kv.Key }
                        | None -> None)
                    |> Seq.toList)

        { Entries = entries
          RefMeta = refMeta
          Comp = WebSharper.Compiler.Compilation(refMeta) }

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
            if mi.MethodName = name && ps = paramDisplays then Some(kv.Key, mi, kv.Value) else None)

    let findCtor (ci: ClassInfo) (argCount: int) =
        ci.Constructors
        |> Seq.tryPick (fun kv ->
            if kv.Key.Value.CtorParameters.Length = argCount then Some kv.Key else None)

    let fieldHashed (e: Entry) (name: string) = name

    let concrete (td: Hashed<TypeDefinitionInfo>) : Concrete<Hashed<TypeDefinitionInfo>> =
        { Generics = []; Entity = td }

    let concreteM (m: Hashed<MethodInfo>) : Concrete<Hashed<MethodInfo>> =
        { Generics = []; Entity = m }

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

    type private MaxHoleProbe() =
        inherit Transformer()
        member val Max = -1 with get, set
        override this.TransformHole(i: int) =
            if i > this.Max then this.Max <- i
            Hole i

    let maxHole (body: Expression) =
        let p = MaxHoleProbe()
        p.TransformExpression body |> ignore
        p.Max

    let hasBody (e: Expression) =
        match e with
        | Undefined -> false
        | _ -> true
