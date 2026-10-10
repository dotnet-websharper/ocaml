(*
 * WebSharper.OCaml: a strongly typed OCaml frontend for WebSharper.
 *
 * Copyright (c) 2026 IntelliFactory.
 * All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *)

open System
open System.IO
open WebSharper.OCaml
open WebSharper.OCaml.Lowering
open WebSharper.Core.JavaScript
open WebSharper.Core.Metadata
open WebSharper.Compiler
open WebSharper.Core.AST

type private CastStripper() =
    inherit Transformer()
    override this.TransformCast(_, e) = this.TransformExpression(e)

let private runtimePrelude () =
    let asm = Reflection.Assembly.GetExecutingAssembly()
    use s = asm.GetManifestResourceStream "wsocaml-runtime.js"
    use r = new StreamReader(s)
    r.ReadToEnd()

let private bindings (refs: ResizeArray<string>) =
    if refs.Count = 0 then None
    else Some(WebSharper.OCaml.Bindings.load (List.ofSeq refs))

let private loadInfo (path: string) : Info =
    let asm = Reflection.Assembly.LoadFrom(Path.GetFullPath path)
    match IO.LoadMetadata asm with
    | Some i -> i
    | None -> failwithf "no WebSharper metadata in %s" path

// Package referenced WebSharper assemblies with the WebSharper packager, and
// emit the WebSharper runtime next to them.
let private packageReferences (refs: string list) (output: string) (pref: Preferences) =
    let infos = refs |> List.map (fun p -> Path.GetFileNameWithoutExtension p, loadInfo p)

    // Prebuilt assemblies carry Ids allocated in a different process, in the same
    // low numeric range that packaging reuses for freshly created Ids. Since
    // `Id` equality/`GetHashCode` are numeric-only, the writer's symbol table
    // then confuses locals with import/module Ids. Advance the allocator well
    // past any serialized Id so packaging only mints disjoint Ids.
    for _ in 1 .. 1_000_000 do
        WebSharper.Core.AST.Id.New() |> ignore

    for (asmName, info) in infos do
        let dir = Path.Combine(output, asmName)
        Directory.CreateDirectory dir |> ignore

        let refMeta =
            infos
            |> List.filter (fun (n, _) -> n <> asmName)
            |> List.map snd
            |> Info.UnionWithoutDependencies

        let res =
            JavaScriptPackager.packageAssembly
                JavaScriptPackager.O.JavaScript
                refMeta
                info
                asmName
                false
                None
                JavaScriptPackager.EntryPointStyle.LibraryBundle

        for (name, stmts) in res do
            let jsAst, _ = JavaScriptWriter.transformProgram Output.JavaScript pref stmts
            File.WriteAllText(Path.Combine(dir, name + ".js"), Writer.ProgramToString pref jsAst)

    let cjs = Reflection.Assembly.Load("WebSharper.Core.JavaScript")
    use s = cjs.GetManifestResourceStream "WebSharper.Core.JavaScript.Runtime.js"
    use r = new StreamReader(s)
    let rtjs = r.ReadToEnd()
    let rtDir = Path.Combine(output, "WebSharper.Core.JavaScript")
    Directory.CreateDirectory rtDir |> ignore
    File.WriteAllText(Path.Combine(rtDir, "Runtime.js"), rtjs)

[<EntryPoint>]
let main argv =
    try
        let mutable input = ""
        let mutable output = "wsocaml-out"
        let mutable compact = false
        let mutable packageRefs = false
        let mutable wsCompile = false
        let references = ResizeArray<string>()

        let rec args i =
            if i < argv.Length then
                match argv[i] with
                | "--ir" ->
                    input <- argv[i + 1]
                    args (i + 2)
                | "--output" ->
                    output <- argv[i + 1]
                    args (i + 2)
                | "--reference" ->
                    references.Add argv[i + 1]
                    args (i + 2)
                | "--package-references" ->
                    packageRefs <- true
                    args (i + 1)
                | "--ws-compile" ->
                    wsCompile <- true
                    args (i + 1)
                | "--compact" ->
                    compact <- true
                    args (i + 1)
                | x -> failwith $"unknown option {x}"

        args 0

        if input = "" then
            failwith "usage: wsocaml --ir file.wsir.json [--output dir] [--compact]"

        let ir = Json.read input

        if ir.Schema <> "wsocaml-ir-4" then
            failwith $"unsupported IR {ir.Schema}"

        Directory.CreateDirectory output |> ignore

        let pref =
            if compact then
                Preferences.Compact
            else
                Preferences.Readable

        let stripper = CastStripper()

        let rec normalize s =
            match s with
            | Import _ | ExportDecl _ -> s
            | Block ss -> Block(ss |> List.map normalize)
            | _ -> stripper.TransformStatement (Breaker.BreakStatement (Breaker.optimizer.TransformStatement s))

        // `[@rpc]` bodies go to a server bundle that registers them by name; the
        // client-side proxies call back through `OCamlRuntime.rpcCall`.
        let writeServerBundle (fns: (string * Expression) list) =
            if not (List.isEmpty fns) then
                let dir = Path.Combine(output, "server")
                Directory.CreateDirectory dir |> ignore

                let stmts =
                    [ for (name, fn) in fns ->
                          ExprStatement(
                              Application(
                                  GlobalAccess(Address.LibAddr [ "OCamlRuntime"; "registerRpc" ]),
                                  [ Value(String name); fn ],
                                  ApplicationInfo.None
                              )
                          ) ]
                    |> List.map normalize

                let jsAst, _ = JavaScriptWriter.transformProgram Output.JavaScript pref stmts
                File.WriteAllText(Path.Combine(dir, ir.Unit + ".js"), runtimePrelude () + Writer.ProgramToString pref jsAst)

        if references.Count > 0 && wsCompile then
            // A'' path: lower member calls to WebSharper nodes and let
            // CompileFull + JavaScriptPackager resolve and package the program
            // (imports, module object and entry) against the referenced metadata.
            let ctx = (bindings references).Value
            ctx.Comp.AssemblyName <- "."
            let stmt, usesRuntime, serverFns = compileEntry (Some ctx) ir
            let comp = ctx.Comp
            comp.SetEntryPoint stmt
            Translator.DotNetToJavaScript.CompileFull comp

            let current = comp.ToCurrentMetadata()

            let pkg =
                JavaScriptPackager.packageAssembly
                    JavaScriptPackager.O.JavaScript
                    ctx.RefMeta
                    current
                    ir.Unit
                    false
                    comp.EntryPoint
                    JavaScriptPackager.EntryPointStyle.RequiredEntryPoint

            for (name, stmts) in pkg do
                let stmts = stmts |> List.map normalize
                let jsAst, _ = JavaScriptWriter.transformProgram Output.JavaScript pref stmts
                let js = Writer.ProgramToString pref jsAst
                // Relative imports of required OCaml units are emitted as
                // "././<unit>.js" (AssemblyName "."); collapse to "./<unit>.js".
                let js = js.Replace("././", "./")
                let js = if usesRuntime then runtimePrelude () + js else js
                let target = if name = "$EntryPoint" then ir.Unit + ".js" else name + ".js"
                File.WriteAllText(Path.Combine(output, target), js)

            packageReferences (List.ofSeq references) output pref
            writeServerBundle serverFns
        else if references.Count = 0 then
            let stmts, usesRuntime, serverFns = compile false None ir
            let ast = stmts |> List.map normalize
            let jsAst, _ = JavaScriptWriter.transformProgram Output.JavaScript pref ast
            let js = Writer.ProgramToString pref jsAst
            let code = if usesRuntime then runtimePrelude () + js else js
            File.WriteAllText(Path.Combine(output, ir.Unit + ".js"), code)
            writeServerBundle serverFns
        else
            let stmts, usesRuntime, serverFns = compile false (bindings references) ir
            let ast = stmts |> List.map normalize
            let jsAst, _ = JavaScriptWriter.transformProgram Output.JavaScript pref ast
            let js = Writer.ProgramToString pref jsAst
            let code = if usesRuntime then runtimePrelude () + js else js
            File.WriteAllText(Path.Combine(output, ir.Unit + ".js"), code)
            writeServerBundle serverFns

        ignore packageRefs

        0
    with e ->
        eprintfn "%s" (e.ToString())
        1
