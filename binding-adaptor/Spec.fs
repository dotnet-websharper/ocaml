(*
 * WebSharper.BindingAdaptor: projection spec.
 *
 * A <pkg>.spec file (JSON) overlays explicit projection decisions on top of the
 * generator's defaults. Initial operations:
 *
 *   modules:  control the OCaml module for a WebSharper type
 *     - type   : WebSharper type full name
 *     - name   : OCaml module name override
 *     - merge  : other WebSharper type full names to merge into this module
 *     - skip   : do not generate this type
 *
 *   members:  control individual OCaml members
 *     - type   : WebSharper type full name
 *     - member : WebSharper member name
 *     - name   : OCaml member name override
 *     - skip   : do not generate this member
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
      Skip: bool }

type MemberSpec =
    { Type: string
      Member: string
      Name: string option
      Skip: bool }

type Spec =
    { Modules: ModuleSpec list
      Members: MemberSpec list }

let empty =
    { Modules = []
      Members = [] }

let private str (e: JsonElement) (n: string) =
    match e.TryGetProperty n with
    | true, v when v.ValueKind = JsonValueKind.String -> Some(v.GetString())
    | _ -> None

let private boolOr (e: JsonElement) (n: string) (d: bool) =
    match e.TryGetProperty n with
    | true, v when v.ValueKind = JsonValueKind.True -> true
    | true, v when v.ValueKind = JsonValueKind.False -> false
    | _ -> d

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
              Skip = boolOr m "skip" false } ]

    let members =
        [ for m in array "members" ->
            { Type = defaultArg (str m "type") ""
              Member = defaultArg (str m "member") ""
              Name = str m "name"
              Skip = boolOr m "skip" false } ]

    { Modules = modules; Members = members }
