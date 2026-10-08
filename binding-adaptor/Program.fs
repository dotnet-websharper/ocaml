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

// Writes <pkg>.opam into the source tree and the repo metadata (with extra-files
// checksums required by opam >= 2.3) into the version directory.
let private finalizeOpamPackage (pkgDir: string) (srcDir: string) (pkgId: string) (opamBody: string) =
    File.WriteAllText(Path.Combine(srcDir, pkgId + ".opam"), opamBody)

    let md5 (path: string) =
        use stream = File.OpenRead path
        use md = System.Security.Cryptography.MD5.Create()
        "md5=" + BitConverter.ToString(md.ComputeHash stream).Replace("-", "").ToLowerInvariant()

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

    File.WriteAllText(Path.Combine(pkgDir, "opam"), opamBody + extraFiles + "\n")

// The shared `Js` module lives in an unwrapped base package so every binding
// package can reference `Js.t` without opening its own wrapper.
let private emitRuntimePackage (outRoot: string) =
    let version = "1.0.0"
    let pkgId = "websharper-runtime"
    let pkgDir = Path.Combine(outRoot, "packages", pkgId, pkgId + "." + version)
    let srcDir = Path.Combine(pkgDir, "files")
    let libDir = Path.Combine(srcDir, "lib")
    Directory.CreateDirectory libDir |> ignore
    File.WriteAllText(Path.Combine(libDir, "js.ml"), jsModule)
    File.WriteAllText(
        Path.Combine(libDir, "dune"),
        "(library\n (name websharper_runtime)\n (public_name websharper-runtime)\n (wrapped false)\n (modules js))\n"
    )
    File.WriteAllText(Path.Combine(srcDir, "dune-project"), "(lang dune 3.0)\n")
    let opam =
        [ "opam-version: \"2.0\""
          "synopsis: \"Shared runtime module (Js) for wsocaml WebSharper bindings\""
          "maintainer: \"IntelliFactory\""
          "authors: \"IntelliFactory\""
          "license: \"Apache-2.0\""
          "homepage: \"https://websharper.com/\""
          "bug-reports: \"https://github.com/dotnet-websharper/issues\""
          "depends: [ \"ocaml\" {>= \"5.0\"} \"dune\" {>= \"3.0\"} ]"
          "build: [ [\"dune\" \"build\" \"-p\" name \"-j\" jobs] ]"
          "" ]
        |> String.concat "\n"
    finalizeOpamPackage pkgDir srcDir pkgId opam


let private lastSegment (fullName: string) =
    let last = fullName.Substring(fullName.LastIndexOf('.') + 1)
    if last.Contains "`" then last.Substring(0, last.IndexOf '`') else last

let gen
    (dll: string)
    (pkgId: string)
    (version: string)
    (outRoot: string)
    (filter: string option)
    (references: string list)
    =
    let info = loadInfo dll

    let classesOf (i: WebSharper.Core.Metadata.Info) (pkg: string) =
        i.Classes
        |> Seq.choose (fun kv ->
            let (a, _custom, ci) = kv.Value
            let td = kv.Key.Value
            match ci with
            | Some ci when a.Address.Length > 0 && validModuleName (classModuleName td a) -> Some(a, td, ci, pkg)
            | _ -> None)
        |> Seq.toList

    let allClasses = classesOf info pkgId

    let localByFull =
        allClasses |> List.map (fun (a, td, _, _) -> td.FullName, classModuleName td a) |> Map.ofList

    let localModules = allClasses |> List.map (fun (a, td, _, _) -> classModuleName td a) |> Set.ofList

    let localArity (m: string) =
        allClasses
        |> List.tryPick (fun (a, td, ci, _) ->
            if classModuleName td a = m then Some ci.Generics.Length else None)
        |> Option.defaultValue 0

    // referenced WebSharper assemblies: types resolve to their generated modules
    let externalClasses =
        references
        |> List.collect (fun refDll -> classesOf (loadInfo refDll) (defaultId refDll))

    // qualified module name (wrapped library), arity, owning package
    let externalByFull =
        externalClasses
        |> List.map (fun (a, td, ci, pkg) ->
            td.FullName, (wrapModule pkg + "." + classModuleName td a, ci.Generics.Length, pkg))
        |> Map.ofList

    let externalSimple =
        externalClasses
        |> List.map (fun (a, td, ci, pkg) ->
            classModuleName td a, (wrapModule pkg + "." + classModuleName td a, ci.Generics.Length, pkg))
        |> Map.ofList

    let deps = System.Collections.Generic.HashSet<string>()

    let env : TypeEnv =
        { LocalModules = localModules
          LocalArity = localArity
          LocalByFull = localByFull
          ExternalByFull = externalByFull
          ExternalSimple = externalSimple
          Deps = deps }

    let selected =
        allClasses
        |> List.filter (fun (a, _, _, _) ->
            match filter with
            | None -> true
            | Some f -> (addressString a).Contains(f, StringComparison.OrdinalIgnoreCase))
        |> List.sortBy (fun (a, _, _, _) -> addressString a)
    let assemblyName = Path.GetFileNameWithoutExtension dll

    let rawModules = selected |> List.map (fun (a, td, ci, _) -> classModuleName td a, ci)
    let nodeSet = rawModules |> List.map fst |> Set.ofList

    let edges =
        rawModules
        |> List.map (fun (m, ci) ->
            let refs =
                referencedModules ci
                |> List.choose (fun fn -> Map.tryFind fn localByFull)
                |> List.filter nodeSet.Contains
                |> Set.ofList
            m, refs)
        |> Map.ofList

    let scc = stronglyConnected (Set.toList nodeSet) edges

    let opaqueFor (m: string) =
        match Map.tryFind m scc with
        | Some comp when comp.Count > 1 -> Set.remove m comp
        | _ -> Set.empty

    let generated =
        selected
        |> List.map (fun (a, td, ci, _) ->
            generateClass env (opaqueFor (classModuleName td a)) assemblyName a td ci)

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

    let libName = pkgId.Replace("-", "_")
    let allModules = unique |> List.map (fun (n, _) -> lowerFirst n)
    let depList =
        ("websharper-runtime" :: (deps |> Seq.filter (fun d -> d <> pkgId && d <> "websharper-runtime") |> Seq.toList))
        |> List.sort
    let duneLib =
        ([ "(library"
           " (name " + libName + ")"
           " (public_name " + pkgId + ")"
           " (modules " + String.concat " " allModules + ")"
           " (libraries " + String.concat " " depList + ")" ]
         @ [ ")" ])
        |> String.concat "\n"
    File.WriteAllText(Path.Combine(libDir, "dune"), duneLib + "\n")
    File.WriteAllText(Path.Combine(srcDir, "dune-project"), "(lang dune 3.0)\n")

    emitRuntimePackage outRoot

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
          yield! [ for d in depList -> "  \"" + d + "\"" ]
          "]"
          "build: ["
          "  [\"dune\" \"build\" \"-p\" name \"-j\" jobs]"
          "]"
          "" ]
        |> String.concat "\n"
    finalizeOpamPackage pkgDir srcDir pkgId opam

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
            let references = ResizeArray<string>()

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
                | "--reference" :: v :: t ->
                    references.Add v
                    parse t
                | [] -> ()
                | x :: _ -> failwith $"unknown option {x}"

            parse rest
            if version = "" then failwith "gen requires --version"
            if dest = "" then failwith "gen requires --dest"
            gen dll id version dest filter (List.ofSeq references)
            0
        | _ ->
            eprintfn
                "usage:\n  binding-adaptor dump <assembly.dll> [--filter <substr>]\n  binding-adaptor gen <assembly.dll> --version <ver> --dest <opam-repo> [--id <pkg-id>] [--filter <substr>] [--reference <assembly.dll>]..."
            2
    with e ->
        eprintfn "%s" (e.ToString())
        1
