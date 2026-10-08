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

    // Assign final (deduped) module names up front, so that intra-module
    // self-references match the emitted (possibly suffixed) module name.
    // A class is a "static helper" if it has no instance members (e.g.
    // WebSharper.UI's non-generic Var holding only static factories).
    let isStaticHelperCi (ci: ClassInfo) =
        (ci.Methods |> Seq.forall (fun kv -> not kv.Value.CompiledForm.IsInstance))
        && (ci.Fields |> Seq.forall (fun kv -> not kv.Value.CompiledForm.IsInstanceField))

    let isDefaultAddr (a: Address) =
        match a.Address with
        | [ "default" ] -> true
        | _ -> false

    // Assign final module names: same-named handwritten classes merge into one
    // module when exactly one is the generic type and the rest are static
    // helpers; other collisions get numeric suffixes.
    let computeFinalNames (cs: (Address * TypeDefinitionInfo * ClassInfo * string) list) =
        let dict = System.Collections.Generic.Dictionary<string, string>()

        let groups = cs |> List.groupBy (fun (a, td, _, _) -> classModuleName td a)

        for baseName, group in groups do
            let sorted = group |> List.sortBy (fun (a, _, _, _) -> addressString a)

            let mergeable =
                List.length sorted > 1
                && sorted |> List.forall (fun (a, _, _, _) -> isDefaultAddr a)
                && (let maxG = sorted |> List.map (fun (_, _, ci, _) -> ci.Generics.Length) |> List.max
                    let primaries = sorted |> List.filter (fun (_, _, ci, _) -> ci.Generics.Length = maxG)
                    let others = sorted |> List.filter (fun (_, _, ci, _) -> ci.Generics.Length <> maxG)
                    List.length primaries = 1 && others |> List.forall (fun (_, _, ci, _) -> isStaticHelperCi ci))

            sorted
            |> List.iteri (fun i (_, td, _, _) ->
                dict.[td.FullName] <- (if mergeable || i = 0 then baseName else baseName + string (i + 1)))

        dict |> Seq.map (fun kv -> kv.Key, kv.Value) |> Map.ofSeq

    let targetNames = computeFinalNames allClasses
    let moduleOf (td: TypeDefinitionInfo) = targetNames.[td.FullName]

    let localByFull =
        allClasses |> List.map (fun (_, td, _, _) -> td.FullName, moduleOf td) |> Map.ofList

    let localModules = allClasses |> List.map (fun (_, td, _, _) -> moduleOf td) |> Set.ofList

    let localArity (m: string) =
        allClasses
        |> List.fold (fun acc (_, td, ci, _) -> if moduleOf td = m then max acc ci.Generics.Length else acc) 0

    // referenced WebSharper assemblies: types resolve to their generated modules
    let externalClasses =
        references
        |> List.collect (fun refDll -> classesOf (loadInfo refDll) (defaultId refDll))

    // qualified module name (wrapped library), arity, owning package
    let externalByFull =
        [ for pkg, cs in externalClasses |> List.groupBy (fun (_, _, _, p) -> p) do
            let names = computeFinalNames cs
            for (a, td, ci, _) in cs do
                yield td.FullName, (wrapModule pkg + "." + names.[td.FullName], ci.Generics.Length, pkg) ]
        |> Map.ofList

    let externalSimple =
        [ for pkg, cs in externalClasses |> List.groupBy (fun (_, _, _, p) -> p) do
            let names = computeFinalNames cs
            for (a, td, ci, _) in cs do
                yield classModuleName td a, (wrapModule pkg + "." + names.[td.FullName], ci.Generics.Length, pkg) ]
        |> Map.ofList

    let deps = System.Collections.Generic.HashSet<string>()

    let selected =
        allClasses
        |> List.filter (fun (a, _, _, _) ->
            match filter with
            | None -> true
            | Some f -> (addressString a).Contains(f, StringComparison.OrdinalIgnoreCase))
        |> List.sortBy (fun (a, _, _, _) -> addressString a)
    let assemblyName = Path.GetFileNameWithoutExtension dll

    let rawModules = selected |> List.map (fun (_, td, ci, _) -> moduleOf td, ci)
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

    let ciOf =
        allClasses
        |> List.map (fun (_, td, ci, _) -> moduleOf td, ci)
        |> Map.ofList

    // Collapse type hierarchies into a single shared type: union classes with
    // their base class / implemented interfaces, and union members of each
    // member-reference cycle (SCC). Members alias the representative, which
    // references no other member, so no module cycle remains and cross-refs no
    // longer fall back to Js.t.
    let parent = System.Collections.Generic.Dictionary<string, string>()
    let find (x: string) =
        let mutable x = x
        while parent.[x] <> x do
            x <- parent.[x]
        x
    let union a b =
        let ra = find a
        let rb = find b
        if ra <> rb then parent.[ra] <- rb
    for m in nodeSet do
        parent.[m] <- m
    let unionFull m (fn: string) =
        match Map.tryFind fn localByFull with
        | Some(r: string) -> if localArity m = 0 && localArity r = 0 then union m r
        | None -> ()
    for (a, td, ci, _) in allClasses do
        let m = moduleOf td
        if nodeSet.Contains m then
            match ci.BaseClass with
            | Some bc -> unionFull m bc.Entity.Value.FullName
            | None -> ()
            for i in ci.Implements do
                unionFull m i.Entity.Value.FullName
    for kv in scc do
        if kv.Value.Count > 1 then
            let ms = kv.Value |> Set.toList |> List.filter (fun m -> localArity m = 0)
            match ms with
            | _ :: _ :: _ ->
                for x in ms.Tail do
                    union ms.Head x
            | _ -> ()

    let groups =
        nodeSet
        |> Set.toList
        |> List.groupBy find
        |> List.map snd
        |> List.filter (fun ms -> List.length ms > 1)

    let indegIn (ms: string list) (m: string) =
        ms
        |> List.sumBy (fun m2 ->
            match Map.tryFind m2 edges with
            | Some rs when rs.Contains m -> 1
            | _ -> 0)

    let hasBase (m: string) =
        match Map.tryFind m ciOf with
        | Some ci -> ci.BaseClass.IsSome
        | None -> false

    // Prefer, as the representative, a root (no base) with the largest subclass
    // tree, so the collapsed type gets a sensible name (e.g. EventTarget).
    let children = System.Collections.Generic.Dictionary<string, ResizeArray<string>>()
    for (a, td, ci, _) in allClasses do
        match ci.BaseClass with
        | Some bc ->
            match Map.tryFind bc.Entity.Value.FullName localByFull with
            | Some b ->
                if not (children.ContainsKey b) then children.[b] <- ResizeArray()
                children.[b].Add(moduleOf td)
            | None -> ()
        | None -> ()

    let descendantCount (root: string) =
        let seen = System.Collections.Generic.HashSet<string>()
        let stack = System.Collections.Generic.Stack<string>()
        stack.Push root
        while stack.Count > 0 do
            let x = stack.Pop()
            match children.TryGetValue x with
            | true, cs ->
                for c in cs do
                    if seen.Add c then stack.Push c
            | _ -> ()
        seen.Count

    let repOf =
        [ for ms in groups do
            if ms |> List.forall (fun m -> localArity m = 0) then
                let rep =
                    ms
                    |> List.sortBy (fun m -> (if hasBase m then 1 else 0), -(descendantCount m + indegIn ms m), m)
                    |> List.head
                for m in ms do
                    yield m, rep ]
        |> Map.ofList

    let collapsed = repOf |> Map.toList |> List.map fst |> Set.ofList

    let env : TypeEnv =
        { LocalModules = localModules
          LocalArity = localArity
          LocalByFull = localByFull
          RepOf = (fun m -> Map.tryFind m repOf)
          ExternalByFull = externalByFull
          ExternalSimple = externalSimple
          Deps = deps }

    let opaqueFor (m: string) =
        match Map.tryFind m scc with
        | Some comp when comp.Count > 1 && not (collapsed.Contains m) -> Set.remove m comp
        | _ -> Set.empty

    let targetAsm = System.Reflection.Assembly.LoadFrom(Path.GetFullPath dll)

    let isAbstract (td: TypeDefinitionInfo) =
        match targetAsm.GetType td.FullName with
        | null -> false
        | t -> t.IsAbstract

    let generated =
        selected
        |> List.map (fun (a, td, ci, _) ->
            generateClass env (opaqueFor (moduleOf td)) assemblyName (isAbstract td) (moduleOf td) a td ci)

    // Merge classes that share the same address into one module (disambiguating
    // member-name clashes); e.g. a generic type and its static-helper type.
    let mergeGroup (gs: GeneratedClass list) =
        match gs with
        | [ g ] -> g
        | _ ->
            let used = System.Collections.Generic.Dictionary<string, int>()

            let uniq (baseName: string) =
                match used.TryGetValue baseName with
                | true, n ->
                    used.[baseName] <- n + 1
                    sprintf "%s_%d" baseName (n + 1)
                | _ ->
                    used.[baseName] <- 1
                    baseName

            let rename (m: Member) = { m with Name = uniq m.Name }
            let best = gs |> List.maxBy (fun g -> g.Generics)

            { best with
                Methods = gs |> List.collect (fun g -> g.Methods) |> List.map rename
                Fields = gs |> List.collect (fun g -> g.Fields) |> List.map rename
                Constructors = gs |> List.collect (fun g -> g.Constructors) |> List.map rename
                Alias = None }

    let unique =
        generated
        |> List.groupBy (fun g -> g.Module)
        |> List.map (fun (name, gs) -> name, mergeGroup gs)

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
