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

[<EntryPoint>]
let main argv =
    try
        let mutable input = ""
        let mutable output = "wsocaml-out"
        let mutable compact = false
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

        let normalize s =
            match s with
            | Import _ | ExportDecl _ -> s
            | _ -> stripper.TransformStatement (Breaker.BreakStatement (Breaker.optimizer.TransformStatement s))

        let stmts, usesRuntime = compile (bindings references) ir

        let ast = stmts |> List.map normalize
        let jsAst, _ = JavaScriptWriter.transformProgram Output.JavaScript pref ast
        let js = Writer.ProgramToString pref jsAst
        let code = if usesRuntime then runtimePrelude () + js else js
        File.WriteAllText(Path.Combine(output, ir.Unit + ".js"), code)
        0
    with e ->
        eprintfn "%s" (e.ToString())
        1
