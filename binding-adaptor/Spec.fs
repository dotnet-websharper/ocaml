(*
 * WebSharper.BindingAdaptor: projection spec.
 *
 * A <pkg>.spec file (JSON) overlays explicit projection decisions on top of the
 * generator's defaults. Operations:
 *
 *   modules:  control the OCaml module for a WebSharper type
 *     - type   : WebSharper type full name
 *     - name   : OCaml module name override
 *     - merge  : other WebSharper type full names to merge into this module
 *     - alias  : make this type an alias to an existing OCaml module's type
 *                (the type is not emitted; references resolve to the module)
 *     - skip   : do not generate this type (accepts "drop" as a synonym)
 *
 *   members:  control individual OCaml members
 *     - type    : WebSharper type full name
 *     - member  : WebSharper member name
 *     - name    : OCaml member name override
 *     - primary : signature of the overload that should get the bare name
 *                 (either a parameter count, or "p0|p1|..." of WebSharper
 *                 parameter display types)
 *     - skip    : do not generate this member (accepts "drop" as a synonym)
 *
 * Copyright (c) 2026 IntelliFactory.
 * SPDX-License-Identifier: Apache-2.0
 *)

module BindingAdaptor.Spec

open System.IO
open System.Text.Json

type ModuleSpec =
    { Type: string
      Name: string option
      Merge: string list
      Alias: string option
      Skip: bool }

type MemberSpec =
    { Type: string
      Member: string
      Name: string option
      Primary: string option
      Skip: bool }

type Spec =
    { Modules: ModuleSpec list
      Members: MemberSpec list
      // When set, module names follow the declaration hierarchy
      // (WebSharper.UI.Client.Elt -> Client.Elt, Html+Elt -> Html.Elt).
      Qualify: bool }

let empty =
    { Modules = []
      Members = []
      Qualify = false }

let private str (e: JsonElement) (n: string) =
    match e.TryGetProperty n with
    | true, v when v.ValueKind = JsonValueKind.String -> Some(v.GetString())
    | _ -> None

let private boolProp (e: JsonElement) (n: string) (d: bool) =
    match e.TryGetProperty n with
    | true, v when v.ValueKind = JsonValueKind.True -> true
    | true, v when v.ValueKind = JsonValueKind.False -> false
    | _ -> d

let private skipOr (e: JsonElement) =
    // "skip" and "drop" are synonyms.
    boolProp e "skip" (boolProp e "drop" false)

let private strList (e: JsonElement) (n: string) =
    match e.TryGetProperty n with
    | true, v when v.ValueKind = JsonValueKind.Array ->
        [ for x in v.EnumerateArray() do
            if x.ValueKind = JsonValueKind.String then yield x.GetString() ]
    | _ -> []

let load (path: string) : Spec =
    use d = JsonDocument.Parse(File.ReadAllText path)
    let root = d.RootElement

    let array (name: string) =
        match root.TryGetProperty name with
        | true, arr when arr.ValueKind = JsonValueKind.Array -> [ for x in arr.EnumerateArray() -> x ]
        | _ -> []

    let modules =
        [ for m in array "modules" ->
            { Type = defaultArg (str m "type") ""
              Name = str m "name"
              Merge = strList m "merge"
              Alias = str m "alias"
              Skip = skipOr m } ]

    let members =
        [ for m in array "members" ->
            { Type = defaultArg (str m "type") ""
              Member = defaultArg (str m "member") ""
              Name = str m "name"
              Primary = str m "primary"
              Skip = skipOr m } ]

    { Modules = modules; Members = members; Qualify = boolProp root "qualified" false }
