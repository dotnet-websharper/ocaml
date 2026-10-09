# binding-adaptor

`binding-adaptor` converts a **WebSharper binding assembly** (a .NET assembly
carrying WebSharper metadata) into an **OCaml opam package** that presents the
same API surface in OCaml. It is the piece that lets OCaml code call
hand-written WebSharper libraries (e.g. `WebSharper.JavaScript`,
`WebSharper.StdLib`, `WebSharper.UI`) with call sites that look like the
original F#.

The generated package is *type-checked by `ocamlc`* (so OCaml code sees real
signatures) and its `external`s carry WebSharper address tags that the OCaml→JS
**backend** resolves against the referenced assemblies at compile time.

```
WebSharper.UI.dll ──▶ binding-adaptor gen ──▶ opam repo: websharper-ui
                                                     │  (lib/*.ml + dune + opam)
                                                     ▼
                       user OCaml  ──ocamlc──▶ type-check
                                   ──backend (ws:)──▶ JS
```

---

## 1. Usage

```
binding-adaptor gen <assembly.dll> --version <ver> --dest <opam-repo>
                    [--id <pkg-id>] [--filter <substr>]
                    [--reference <assembly.dll>]...   # repeatable
                    [--spec <file.spec>]
```

- `--id` defaults to `websharper-<name>` (name = assembly basename with the
  `WebSharper.` prefix stripped, lower-cased, `.`/`_` → `-`).
- `--reference` assemblies are loaded for cross-package type resolution; the
  generated package gains a matching `depends:` entry.
- `--spec` overrides the projection spec (see §10); otherwise a spec named
  `<pkg-id>.spec` is looked up beside the assembly or in `./specs/`.
- `--filter` restricts generation to classes whose address contains a substring
  (used for experiments and the test harness).

Example (as used by `scripts/` and the README of the repo):

```
dotnet binding-adaptor.dll gen \
  ~/.nuget/packages/websharper.ui/10.1.5.676/lib/netstandard2.0/WebSharper.UI.dll \
  --version 10.1.5 --dest ./bindings \
  --reference .../WebSharper.JavaScript.dll --reference .../WebSharper.StdLib.dll
```

`binding-adaptor dump <assembly.dll> [--filter <substr>]` prints the raw
metadata (classes, methods, fields, constructors and compiled-member kinds) and
is the main tool for understanding what a binding contains.

---

## 2. Input: WebSharper metadata

The assembly's embedded metadata (`WebSharper.Core.Metadata.IO.LoadMetadata`) is
the sole input. It maps every type to a `ClassInfo` (methods, fields,
constructors), an `Address` (its JS location) and a `CustomTypeInfo`.

Two address shapes matter:

| `Address.Module` / list | meaning | example |
|---|---|---|
| `DotNetType _`, `["default"]` (`TypeDefaultExport`) | a JS **object** type (has a prototype) | `WebSharper.UI.Attr` |
| `DotNetType _`, `[]` (`TypeModuleRoot`) | a module-root type (static class, no prototype) | `WebSharper.UI.HtmlModule.on` |

`Address.ToString()` is the qualified address used in tags, e.g.
`WebSharper.UI/WebSharper.UI.Attr::default` or
`WebSharper.UI/WebSharper.UI.HtmlModule.on::`.

Many binding types are declared with `[<JavaScript>]` and either a `default`
export (runtime classes) or an empty module-root address (static helpers).

---

## 3. Class selection

A metadata class becomes an OCaml module when **all** hold:

- it has a `ClassInfo`;
- its derived module name is a valid OCaml module identifier;
- it is **usable** — has at least one member a caller can supply from OCaml:
  a method whose parameters are all non-quotation, or any field, or any
  constructor. Classes whose only members take `Expr<…>` (the server-side
  counterparts of a client proxy) and member-less stubs are dropped;
- it is **publicly visible** (`Type.IsVisible` via the loaded assembly);
- its full name does not contain `$` (`$StartupCode*` static-initializer
  holders, compiler-generated);
- it is not skipped by the spec.

---

## 4. Module naming

Every class gets a **module name**. Two modes:

### 4.1 Default (flat, address-derived)

- If the address has a JS path (`Address.Address` is non-empty and not
  `["default"]`), the last path segment is used (arity stripped): a JS class
  `globalThis.Element` → `Element`.
- Otherwise (handwritten `[<JavaScript>]` types) the .NET simple type name is
  used (`WebSharper.UI.Attr` → `Attr`).
- The first letter is upper-cased (`on` → `On`).

### 4.2 Qualified names (`"qualified": true`)

Designed for packages like `WebSharper.UI` whose namespaces/modules reuse simple
names. The **declaration path** is derived from `TypeDefinitionInfo.FullName`
after stripping the assembly root namespace, splitting on `.` and `+`, stripping
arity and a trailing `Module` segment (`HtmlModule` → `Html`):

```
WebSharper.UI.Elt                     -> Elt
WebSharper.UI.Client.Elt              -> ClientElt
WebSharper.UI.HtmlModule+Elt          -> HtmlElt          (parent Html + Elt)
WebSharper.UI.HtmlModule+SvgElements+Elt -> SvgElementsElt
```

i.e. a type not directly in the root namespace is named
`<immediateParent><Leaf>`. This removes the numeric dedup suffixes that flat
naming would otherwise produce (`Attr2`, `Elt4`, …).

> **Why not nested modules (`Html.Elt`)?** A single-file dune library wraps each
> file as a submodule and compiles members with the wrapper opened. Nested
> submodules then either shadow same-named top-level modules or trip OCaml's
> "current compilation unit" alias error. Qualified flat names avoid both.

### 4.3 Collisions

Classes that resolve to the same module name are grouped:

- they **merge** into one module when the spec forces it (`merge`) or when
  exactly one is the generic type (largest arity) and all others are
  **static helpers** (no instance methods/fields) — this coalesces F# `type X<'T>`
  with its `module X`. For `qualified` packages the address check is relaxed
  (helpers are often module-root types);
- otherwise each gets a numeric suffix on the last segment (`Foo`, `Foo2`, …),
  ordered so prototype-bearing types keep the bare name.

---

## 5. Type conversion

`Type` (WebSharper AST) → OCaml type string. Builtins:

| WebSharper / .NET | OCaml |
|---|---|
| `System.Void` | `unit` |
| `System.Boolean` | `bool` |
| `System.String` | `string` |
| `System.Char` | `char` |
| `SByte` `Byte` `Int16` `UInt16` `Int32` `UInt32` | `int` |
| `Int64` `UInt64` | `int64` |
| `Single` `Double` | `float` |
| `System.Object` | `Js.t` |

Other rules:

- **Concrete type** → look up its module and arity. If found,
  `<Module>.t` with the type arguments applied (`('a, 'b) Foo.t`). If the module
  is being generated itself, it is just `t`. If not found, the type degrades to
  `Js.t`.
- **Type parameter** `i` → `'a`, `'b`, … (`typeParamName`).
- **Array** → `('a) array`.
- **Tuple** → `'a * 'b * …`.
- **`FSharpFuncType(a, b)`** → `(a -> b)` — an OCaml function type. This is what
  lets callbacks (`Elt.on`, `View.map`, `On.click`, …) be written as OCaml
  closures; the backend bridges them to JS (§12).
- **`ByRef`** → the underlying type.
- Anything else → `Js.t`.

### `IEnumerable` parameters are lists

A **parameter** typed `System.Collections.Generic.IEnumerable<T>` becomes
`(T) list` (non-generic `IEnumerable` → `Js.t list`); return and field types
stay opaque (`WebSharper_StdLib.IEnumerable2.t`). The backend converts the list
to a JS array at the call boundary (§12), so combinators read:

```ocaml
open WebSharper_UI.Html
div [ On.click (fun _ _ -> …) ] [ Doc.text "hi" ]
```

---

## 6. Members

### Methods

For each `ClassInfo` method:

- **Instance-ness.** A method is presented as an instance member (receiver
  first) when its compiled form is instance, or — for inline members — when its
  inline body references a hole at index ≥ parameter count.
- **Signature.** `recv -> p0 -> p1 -> … -> ret` (or `p0 -> … -> ret` for
  statics). Receiver is `t`/`('a) t` per the module arity. No-argument members
  become `unit -> ret`.
- **Overloads.** Ordered by the spec `primary` (if any), then non-array
  signatures, then fewest parameters; the first gets the bare name, the rest get
  `_2`, `_3`, … via a uniqueness pass.
- **Name.** From the spec `name` if given, else `memberName` (see below), then
  `sanitize`.
- **Tag.** `ws:<asm>!<address>#<Method>|<type0>|<type1>|…` where each
  `<typeN>` is `typeDisplay` (e.g. `System.String`, `fn`, `'0`).

### Fields

Each `ClassInfo` field yields `get_<field>` and, unless read-only,
`set_<field>` (`t -> ty` / `t -> ty -> unit`; static fields drop the receiver).
Tags: `wsget:<asm>!<address>#<Field>` / `wsset:…`.

### Constructors

Each constructor yields `create : p0 -> … -> t` with tag `wsnew:<asm>!<address>`.
No-argument constructors take `unit`. **Abstract classes have no constructor**
(`new Abstract()` yields an empty object); their instances come from static
factory methods.

### Kinds (comments only)

`renderMember` emits a comment with the member's kinds — a comma list of
`static, instance, func, globalfunc, new, inline, macro` — purely documentary.

### Property accessors

WebSharper encodes properties as `get_X`/`set_X` methods. `memberName` collapses
them to the property name when the character after the prefix is uppercase:

```
get_Empty   -> empty
set_Value   -> set_value
get_value   -> get_value        (left alone; not a property)
```

### Name sanitization

Member/field names are lower-cased at the first character, non-identifier
characters are stripped, a leading digit gets a `_` prefix, an empty name
becomes `x`, and OCaml keywords (including OCaml 5's `effect`) get a trailing
`_`.

---

## 7. Cross-package references and dependencies

With `--reference`, each referenced assembly is loaded and its classes indexed by
fully-qualified name → `(module path, arity, package)`. When a member signature
mentions a referenced type it is emitted **qualified** (`WebSharper_JavaScript.Element.t`,
`WebSharper_StdLib.FSharpOption.t`) and the package id is added to the generated
`depends:`.

---

## 8. Cyclic types

Two mechanisms keep the generated OCaml acyclic while preserving real types.

### 8.1 Collapsed hierarchies (`RepOf`)

A class hierarchy that is cyclic *and* whose members all have arity 0 (e.g. the
DOM `EventTarget`/`Node`/`Element`/`Document` graph) is collapsed to a single
representative type: one module declares `type t`, the others become
`type t = Rep.t`, and all references are redirected to the representative. The
representative is chosen as the base with the largest subclass tree.

### 8.2 Type-split for module cycles

A stronger cycle (e.g. `Var`/`View`/`ViewBuilder`) cannot be collapsed without
losing type distinctions. Instead the cycle is broken **structurally**: a shared
`<members>Types` module holds the abstract types, and each member file aliases
its type and refers to siblings through the types module:

```ocaml
(* varViewViewBuilderTypes.ml *)
module Var         = struct type ('a) t end
module View        = struct type ('a) t end
module ViewBuilder = struct type t end

(* var.ml *)
type ('a) t = ('a) VarViewViewBuilderTypes.Var.t
external view : ('a) t -> ('a) VarViewViewBuilderTypes.View.t = "ws:…"
```

Member files then depend only on the types module (a DAG), so no opacity is
needed and `Var.view : 'a Var.t -> 'a View.t` stays fully typed. This is also
what lets F# type+module pairs coalesce (see §4.3).

---

## 9. Emission

For an assembly `WebSharper.UI` the package layout is:

```
packages/websharper-ui/websharper-ui.<ver>/
  opam                     # metadata + extra-files md5 hashes
  files/
    dune-project
    dune                   # wrapped library (name webSharper_UI, public_name websharper-ui)
    lib/<module>.ml        # one file per module (lower-cased name)
  websharper-ui.opam       # copy written into the source tree
```

- The library is **wrapped**: `(name webSharper_UI)` exposes modules as
  `WebSharper_UI.<Module>`.
- The shared runtime module `Js` lives in an unwrapped base package
  `websharper-runtime` (`(wrapped false)`), so every binding package can use
  `Js.t` without opening its own wrapper.
- The `lib/` directory is cleaned before each run so renames do not leave stale
  files.
- `opam` records `extra-files:` with md5 checksums (required by opam ≥ 2.3 for
  local sources).

A generated module file looks like:

```ocaml
(* Generated by binding-adaptor. Do not edit. *)
type t
(* inline *)
external get_Empty : unit -> t = "ws:WebSharper.UI!WebSharper.UI/WebSharper.UI.Attr::default#get_Empty|" "…"
(* static *)
external newA2 : t -> t -> t = "ws:WebSharper.UI!…WebSharper.UI.Attr::default#NewA2|WebSharper.UI.Attr|WebSharper.UI.Attr" "…"
```

Each `external` repeats the tag (the backend reads one of the two annotations).

---

## 10. Projection spec (`<pkg>.spec`)

A JSON file overlaying explicit decisions (see `specs/websharper-ui.spec`):

```json
{
  "qualified": true,
  "modules": [
    { "type": "WebSharper.UI.Var`1", "name": "Var", "merge": ["WebSharper.UI.Var"] },
    { "type": "WebSharper.UI.HtmlModule", "name": "Html" },
    { "type": "WebSharper.UI.Client.HtmlExtensions+on", "name": "On" },
    { "type": "WebSharper.UI.Storage`1", "merge": ["WebSharper.UI.Storage"] }
  ],
  "members": [
    { "type": "WebSharper.UI.Doc", "member": "TextNode", "name": "text" },
    { "type": "WebSharper.UI.Doc", "member": "RunById", "name": "runById" },
    { "type": "WebSharper.UI.Var", "member": "Create", "primary": "1" }
  ]
}
```

| key | effect |
|---|---|
| `qualified` (top level) | enable §4.2 qualified module names |
| `modules[].name` | force a module name (may be dotted) |
| `modules[].merge` | merge the listed type full names into this module |
| `modules[].alias` | make this type an alias of another module's `t` (not emitted) |
| `modules[].skip` / `drop` | do not generate this type |
| `members[].name` | override a member's OCaml name |
| `members[].primary` | which overload gets the bare name (param count, or `p0|p1|…`) |
| `members[].skip` / `drop` | do not generate this member |

Reference packages' specs are loaded and applied when resolving their types.

---

## 11. Relationship to the backend

The generated `external`s are inert to `ocamlc` (they only type-check). At
compile time the **backend** (`backend/`, `--ws-compile`) parses each tag and
emits WebSharper AST against the referenced metadata:

| tag scheme | emitted |
|---|---|
| `ws:<asm>!<addr>#<Member>\|types` | static/instance call (`Call`/thin access); inline bodies are inlined; macros error in the old path but are validated under A″ |
| `wsnew:<asm>!<addr>` | `Ctor`/`new` |
| `wsget:<asm>!<addr>#<Field>` | field/property get |
| `wsset:<asm>!<addr>#<Field>` | field/property set |

The address qualifier (`<asm>!<addr>` plus the member name and parameter type
displays) must match what `binding-adaptor` emitted; both come from the same
metadata.

### Runtime bridges (OCaml values → JS)

Arguments are adapted at the call boundary:

- A `fn` parameter (`FSharpFuncType`) receives the OCaml closure wrapped by
  `caml_to_js`, which makes it callable curried `f(a)(b)` (and trampolines tail
  calls) as WebSharper expects;
- an `IEnumerable` parameter receives the OCaml list wrapped by
  `caml_list_to_array` (WebSharper accepts a JS array as an `IEnumerable`).

---

## 12. Excluded members

- **Quotation members** — any member with an `Expr<…>` parameter is not usable
  from OCaml (there are no quotations). A class whose only members are of this
  kind is dropped; otherwise the member is still emitted but is a `Js.t`-typed
  stub.
- **Proxy representation members** — when a type is the target of a
  `[<Proxy>]`-marked internal type, WebSharper folds the proxy's union cases onto
  the public type as `New<Case>` constructors (e.g. `Attr.NewA1..4`). These are
  internal representation, not API, and are omitted.
- **`$StartupCode*`** and other compiler-generated types.
- Anything named out by the spec.

---

## 13. Known limitations

- Nested OCaml modules are not produced (see §4.2); names are flat/qualified.
- Non-public or otherwise unrepresentable types degrade to `Js.t`.
- The generated bindings cover the JS-facing metadata; server-only members that
  take quotations are only present as stubs (or omitted).
- Correct cross-assembly compilation depends on the backend's id handling
  (prebuilt assemblies reuse numeric ids; the packager must mint disjoint ones).
