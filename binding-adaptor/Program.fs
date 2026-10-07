(*
 * WebSharper.BindingAdaptor: projects WebSharper binding packages to OCaml opam packages.
 *
 * Copyright (c) 2026 IntelliFactory.
 * All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *)

module BindingAdaptor.Program

open System
open System.IO
open System.Reflection
open System.Text
open WebSharper.Core
open WebSharper.Core.AST
open WebSharper.Core.Metadata
open BindingAdaptor.Generator

let loadInfo (path: string) : Info =
    let asm = Assembly.LoadFrom(Path.GetFullPath path)
    match IO.LoadMetadata asm with
    | Some i -> i
    | None -> failwithf "no WebSharper metadata found in %s" path

let addressString (a: Address) = String.concat "." a.Address

let private defaultId (dll: string) =
    let name = Path.GetFileNameWithoutExtension dll
    let name =
        if name.StartsWith("WebSharper.", StringComparison.OrdinalIgnoreCase) then name.Substring 11
        else name
    "websharper-" + name.ToLowerInvariant().Replace('.', '-').Replace('_', '-')

let dump (dll: string) (filter: string option) =
    let info = loadInfo dll
    let matches (a: Address) =
        match filter with
        | None -> true
        | Some f -> (addressString a).Contains(f, StringComparison.OrdinalIgnoreCase)

    let classes =
        info.Classes
        |> Seq.choose (fun kv ->
            let (a, _custom, ci) = kv.Value
            match ci with
            | Some ci when matches a -> Some(a, ci)
            | _ -> None)
        |> Seq.sortBy (fun (a, _) -> addressString a)

    let mutable nClasses = 0
    let mutable nMethods = 0
    for (a, ci) in classes do
        nClasses <- nClasses + 1
        printfn "%s" (addressString a)
        for kv in ci.Methods do
            nMethods <- nMethods + 1
            printfn "    .%A [%s]" kv.Key (methodKinds kv.Value.CompiledForm)
        for kv in ci.Fields do
            printfn "    field %s [%s]" kv.Key (fieldKinds kv.Value.CompiledForm)
        for kv in ci.Constructors do
            printfn "    ctor .%A [%s]" kv.Key (methodKinds kv.Value.CompiledForm)
    printfn ""
    printfn "%d classes, %d methods" nClasses nMethods

let private jsModule =
    [ "type t"
      "external of_js : 'a -> t = \"%identity\""
      "external to_js : t -> 'a = \"%identity\""
      "external get : t -> string -> t = \"jsdget\""
      "external set : t -> string -> t -> unit = \"jsdset\""
      "external get_index : t -> int -> t = \"jsdget\""
      "external set_index : t -> int -> t -> unit = \"jsdset\""
      "" ]
    |> String.concat "\n"

let private lastSegment (fullName: string) =
    let last = fullName.Substring(fullName.LastIndexOf('.') + 1)
    if last.Contains "`" then last.Substring(0, last.IndexOf '`') else last

let gen (dll: string) (pkgId: string) (version: string) (outRoot: string) (filter: string option) =
    let info = loadInfo dll

    let allClasses =
        info.Classes
        |> Seq.choose (fun kv ->
            let (a, _custom, ci) = kv.Value
            match ci with
            | Some ci -> Some(a, ci)
            | None -> None)
        |> Seq.toList

    let moduleSet =
        allClasses
        |> List.map (fun (a, _) -> classModuleName a)
        |> Set.ofList

    let arityOf (m: string) =
        allClasses
        |> List.tryFind (fun (a, _) -> classModuleName a = m)
        |> Option.map (fun (_, ci) -> ci.Generics.Length)
        |> Option.defaultValue 0

    let selected =
        allClasses
        |> List.filter (fun (a, _) ->
            match filter with
            | None -> true
            | Some f -> (addressString a).Contains(f, StringComparison.OrdinalIgnoreCase))
        |> List.sortBy (fun (a, _) -> addressString a)
    let assemblyName = Path.GetFileNameWithoutExtension dll

    let rawModules = selected |> List.map (fun (a, ci) -> classModuleName a, ci)
    let nodeSet = rawModules |> List.map fst |> Set.ofList

    let edges =
        rawModules
        |> List.map (fun (m, ci) -> m, (referencedModules ci |> List.filter nodeSet.Contains |> Set.ofList))
        |> Map.ofList

    let scc = stronglyConnected (Set.toList nodeSet) edges

    let opaqueFor (m: string) =
        match Map.tryFind m scc with
        | Some comp when comp.Count > 1 -> Set.remove m comp
        | _ -> Set.empty

    let generated =
        selected
        |> List.map (fun (a, ci) ->
            generateClass moduleSet arityOf (opaqueFor (classModuleName a)) assemblyName a ci)

    let used = System.Collections.Generic.HashSet<string>()
    let unique =
        generated
        |> List.map (fun g ->
            let mutable name = g.Module
            let mutable i = 2
            while used.Contains name do
                name <- g.Module + string i
                i <- i + 1
            used.Add name |> ignore
            name, g)

    let pkgDir = Path.Combine(outRoot, "packages", pkgId, pkgId + "." + version)
    let srcDir = Path.Combine(pkgDir, "files")
    let libDir = Path.Combine(srcDir, "lib")
    Directory.CreateDirectory libDir |> ignore

    for (name, g) in unique do
        let g = { g with Module = name }
        File.WriteAllText(Path.Combine(libDir, lowerFirst name + ".ml"), renderClass g)

    File.WriteAllText(Path.Combine(libDir, "js.ml"), jsModule)

    let libName = pkgId.Replace("-", "_")
    let allModules = "js" :: (unique |> List.map (fun (n, _) -> lowerFirst n))
    let duneLib =
        [ "(library"
          " (name " + libName + ")"
          " (public_name " + pkgId + ")"
          " (wrapped false)"
          " (modules " + String.concat " " allModules + "))"
          "" ]
        |> String.concat "\n"
    File.WriteAllText(Path.Combine(libDir, "dune"), duneLib)
    File.WriteAllText(Path.Combine(srcDir, "dune-project"), "(lang dune 3.0)\n")

    let opam =
        [ "opam-version: \"2.0\""
          "synopsis: \"OCaml bindings for " + assemblyName + "\""
          "description: \"Generated by binding-adaptor from " + assemblyName + ".dll.\""
          "maintainer: \"IntelliFactory\""
          "authors: \"IntelliFactory\""
          "license: \"Apache-2.0\""
          "homepage: \"https://websharper.com/\""
          "bug-reports: \"https://github.com/dotnet-websharper/issues\""
          "depends: ["
          "  \"ocaml\" {>= \"5.0\"}"
          "  \"dune\" {>= \"3.0\"}"
          "]"
          "build: ["
          "  [\"dune\" \"build\" \"-p\" name \"-j\" jobs]"
          "]"
          "" ]
        |> String.concat "\n"
    File.WriteAllText(Path.Combine(srcDir, pkgId + ".opam"), opam)

    // opam >= 2.3 only copies files declared in extra-files.
    let md5 (path: string) =
        use stream = File.OpenRead path
        use md = System.Security.Cryptography.MD5.Create()
        let hash = md.ComputeHash stream
        "md5=" + BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant()

    let allFiles =
        Directory.EnumerateFiles(srcDir, "*", SearchOption.AllDirectories)
        |> Seq.map (fun p -> Path.GetRelativePath(srcDir, p).Replace('\\', '/'))
        |> Seq.sort
        |> Seq.toList

    let extraFiles =
        [ "extra-files: ["
          for f in allFiles do
              "  [\"" + f + "\" \"" + md5 (Path.Combine(srcDir, f)) + "\"]"
          "]" ]
        |> String.concat "\n"

    File.WriteAllText(Path.Combine(pkgDir, "opam"), opam + extraFiles + "\n")

    printfn "generated %d modules -> %s" (List.length unique) pkgDir

[<EntryPoint>]
let main argv =
    try
        match List.ofArray argv with
        | "dump" :: dll :: rest ->
            let filter =
                match rest with
                | ["--filter"; f] -> Some f
                | _ -> None
            dump dll filter
            0
        | "gen" :: dll :: rest ->
            let mutable id = defaultId dll
            let mutable version = ""
            let mutable dest = ""
            let mutable filter = None

            let rec parse =
                function
                | "--id" :: v :: t ->
                    id <- v
                    parse t
                | "--version" :: v :: t ->
                    version <- v
                    parse t
                | "--dest" :: v :: t ->
                    dest <- v
                    parse t
                | "--filter" :: v :: t ->
                    filter <- Some v
                    parse t
                | [] -> ()
                | x :: _ -> failwith $"unknown option {x}"

            parse rest
            if version = "" then failwith "gen requires --version"
            if dest = "" then failwith "gen requires --dest"
            gen dll id version dest filter
            0
        | _ ->
            eprintfn
                "usage:\n  binding-adaptor dump <assembly.dll> [--filter <substr>]\n  binding-adaptor gen <assembly.dll> --version <ver> --dest <opam-repo> [--id <pkg-id>] [--filter <substr>]"
            2
    with e ->
        eprintfn "%s" (e.ToString())
        1
