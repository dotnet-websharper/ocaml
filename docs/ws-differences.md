# Differences from .NET WebSharper

wsocaml compiles the same source to both tiers and reuses WebSharper's AST, runtime
and binding packages, so most of the programming model carries over unchanged
(`Doc`/`Var`/`View`, `Attr`/`On`, sitelets, templates). This document records where
the two deliberately differ, why, and what is not implemented yet. It also collects
the known gaps otherwise scattered across the other design notes.

## 1. Instance members and the object model

.NET WebSharper exposes most interop APIs as CLR classes with instance members:
`var.Get()`, `view.V`, `doc.RunById`, `doc.Input`. wsocaml's generated bindings
expose the same operations as **functions taking the receiver as the first
argument**:

```ocaml
Var.get  : 'a Var.t -> 'a
Doc.runById : string -> Doc.t -> unit
```

The frontend does not support OCaml method sends — `Lsend` is the single
unimplemented Lambda primitive (`frontend/bin/main.ml`:

```ocaml
| Lsend _ -> failwith "objects/method sends are not supported yet"
```

### This is a representation choice, not a missing mechanism

WebSharper already has two representations for a type, chosen with
`[<Prototype>]` / `[<Prototype(false)>]` (`WebSharper.PrototypeAttribute`):

- **default** — a real JavaScript class: methods live on `X.prototype` and calls are
  property sends `obj.m(args)`;
- **`[<Prototype(false)>]`** — a plain object: the compiler sets `ForceNoPrototype`
  and rewrites every instance method into a static function with `this` prepended,
  and the constructor into a plain-object factory (`WebSharper.Compiler`,
  `Compilation.fs` `ForceNoPrototype`; `Translator.fs` `staticCall`).

The flattened `recv -> args -> ret` surface wsocaml emits is exactly the
`[<Prototype(false)>]` representation — one WebSharper itself defines.

### Prototype hookup

When a value arrives as a plain object (deserialized JSON, a DOM object) but should
behave as a class instance, WebSharper reattaches the prototype:

```js
Object.assign(Object.create(ctor.prototype), fields)   // WebSharperRuntime.Create
```

via the runtime helpers `Create` / `Clone`
(`WebSharper.Core.JavaScript/Runtime.js`), emitted for copy-constructors
(`Translator.TransformCopyCtor`), plus `Object.setPrototypeOf` /
`getPrototypeOf` exposed through `JS`. The JSON on the wire carries only the data
fields; the methods come from the rechained prototype.

### Why not OCaml objects?

An object's *shape* maps to a JavaScript object fine — but a record already maps to
a JS object (`docs/client-server.md`), so shape alone gains nothing. The extra
parts of an object (methods, `self`, mutable state, inheritance, closures) don't
survive a JSON round-trip, and OCaml objects are *structural* (open rows, `#m` on
any compatible row, coercions `:>`, `inherit`, `self`-typing) while WS classes are
nominal prototypes.

Supporting instance members would mean (a) lowering `Lsend`, and (b) binding interop
types as WebSharper classes (`[<Prototype>]`) so `obj#m` lowers to a property send,
using `Create` / `setPrototypeOf` for plain/JSON values. The prototype plumbing
already exists; the work is the frontend lowering and the class↔object ABI. Pure
OCaml `object … end` is separate: it would also require lowering OCaml's own object
encoding (method table + `self` + `inherit`/coercions), so it is out of scope for
now.

### Consequence for the generated API

Because members are functions, member syntax like `view.V` cannot be written; the
faithful spelling is the flattened accessor (see §2). This is also why the template
surface is a **record with pipe combinators, not a class**
(`docs/templates.md` §2).

> A related wart: `binding-adaptor` decides instance-ness from a member's
> *compiled form* (`binding-adaptor/Generator.fs`: `isInstance = form.IsInstance ||
> (form.IsInline && …)`). WebSharper records a `[<Macro>]` member's form as
> `Macro`, so a macro *instance* property such as `View.V` / `Var.V` loses its
> receiver and is emitted as `unit -> 'a` instead of `'a View.t -> 'a`. That is the
> concrete bug behind §2.

## 2. `V` reactive notation

.NET WebSharper's `V` notation lets reactive code read like ordinary code — a
`.V` on a `Var`/`View` inside a `V`-enabled call (or a `V (…)` argument) is lifted
to `View.Map` / `Map2` / `Apply`:

```fsharp
let a = Var.Create 1
let b = Var.Create 2
let sum = V (a.V + b.V)                         // View.Map2 (fun x y -> x + y)
let label = V (sprintf "%d + %d" a.V b.V)
textView (sprintf "sum: %d" (a.V + b.V))        // V-enabled: textView/Attr.Style/…
```

**Status: not supported.** `V.v` (the `WebSharper.UI.V.V` macro) and the inner
`get_V` accessors are present in the generated binding, but two blockers prevent use:

1. **Generic type arguments are lost.** `Macros.V` reads `call.Method.Generics[0]`
   for the resolved `'T`, but the backend builds every method with `Generics = []`
   (`backend/Bindings.fs` `concreteM`); wsocaml never resolves the concrete type
   arguments at a `ws:` call site. So even the non-reactive case `V.v "hi"` fails at
   `--ws-compile`:
   `Macro error in WebSharper.UI.Macros+V.TranslateCall: … Parameter 'n'`.
   Any generic WS macro (also the `V`-enabled `TextView`, `AttrCreate`, …) is
   affected.
2. **The receiver is dropped for the `.V` accessor** (see the note in §1): `Var.v`
   and `View.v` are emitted as `unit -> 'a`, so `a.V` cannot be spelled at all.

### What it would look like, if fixed

The member access `x.V` becomes the flattened accessor `Var.v x` / `View.v x`, and
`V e` becomes `V.v e`:

| .NET F# | wsocaml (proposed) |
| --- | --- |
| `V 12` | `V.v 12` |
| `V (a.V + b.V)` | `V.v (Var.v a + Var.v b)` |
| `V ("b" + string v.V)` | `V.v ("b" ^ string_of_int (View.v v))` |
| `Attr.Style "w" (string (a.V + b.V))` | `Attr.style "w" (string_of_int (Var.v a + Var.v b))` |
| `p [Attr.ClassPred "big" (a.V > 10)] …` | `p [Attr.classPred "big" (Var.v a > 10)] …` |
| `textView (sprintf "%d" n.V)` | `Doc.textView (Printf.sprintf "%d" (Var.v n))` |

`Var.v` (the placeholder, WebSharper's `get_V`) sits next to the real accessors
`Var.get` (`Get()`) and `Var.value` (`get_Value`) — all three are
`'a Var.t -> 'a`, so this needs documenting wherever it appears.

Fixing it needs (a) inferring/attaching resolved generic type args when lowering
`ws:` calls, and (b) giving macro instance members a receiver in `binding-adaptor`
(via CLR reflection, since the metadata does not record instance-ness for macros).

## 3. Other known gaps

Consolidated; see the linked note for detail.

- **Binding `open`s shadow, and the editor checks different modules than the
  build** — `open WebSharper_UI` after `open WebSharper_JavaScript` hides
  `Storage`/`Array`/`Attr`/`Notation` (qualify the DOM side or alias it:
  `module JsStorage = WebSharper_JavaScript.Storage`), and `examples/*/dune`
  typechecks against the native *shadow* (`websharper-ui-server`, 19 submodules)
  while `build.sh`/the suite use the generated `websharper-ui` binding (80), so a
  bare `Storage`/`Array` may typecheck in the editor and fail in the build (or the
  reverse). README → *Name collisions and shadowing* has the tables.
- **`IEnumerable<'T>` is presented as OCaml `Seq.t`** (it used to be an opaque
  `IEnumerableOf.t` for results). The generator maps it in *both* directions and
  the backend converts where a value crosses the OCaml/JS boundary
  (`js_to_caml_seq` / `caml_seq_to_js`: a WebSharper `IEnumerable` is a
  `{ GetEnumerator() }` object, an OCaml `Seq.t` is `unit -> node`). `IEnumerable`
  *parameters* are still OCaml `list`s by default (so `div [attrs] [docs]` reads
  well); a spec's `"seqParams": true` marks the sequence-processing modules
  (`SeqModule`, `ListModule`, `LinqEnumerable`), whose parameters become
  `'T Seq.t` and whose results (`Seq.t`) are consumable with `List.of_seq`.
  The client bundle ships `Seq`/`List` shims (`frontend/bin/gen_stdlib_shim.ml`)
  whose `of_seq`/`Seq.*` accept *either* representation, so a sequence that is
  still inside a WebSharper container (e.g. the `seq` of a
  `View.mapSeqCached*`) is consumable without an explicit conversion. Edges: an
  OCaml-built `Seq.t` nested in a WebSharper container that a WebSharper member
  then enumerates is not converted; conversion materialises (so infinite
  sequences are not supported).
- **Objects / method sends** — §1: `Lsend` unsupported; interop is function-shaped.
- **`V` notation** — §2: generic type args not resolved; `.V` receiver dropped.
- **Templates** (`docs/templates.md` §7):
  - `ws-anchor` is parsed but not resolved;
  - cross-file instantiation (`ws-file.Tpl`) is not implemented (`references = []`);
  - `ws-dom` and `datetime-local`/`dateTimeLocal` vars fall back to `string`;
  - `ServerLoad`/`ClientLoad` are not configurable (source is always embedded);
  - a template used directly in a server page is static, not hydrated in place.
- **Routing** (`docs/routing.md` §13):
  - client-side `Router.installHash` works (the `websharper-sitelets` binding +
    a shadow), but its server side is a **no-op** (there is no URL to parse);
  - `Router.Infer` (the type-provider that reads `[<EndPoint>]` attributes) is a
    compile-time macro and is not available — build routers with
    `RouterModule.table`/`single`/`shift`/`sum`/`map` instead;
  - `Router`'s path/query combinators that take F# collections/`Func` (`create`,
    `createWithQuery`, `query*`, `body`, `fetch`, `xHR`) are bound but not
    shadowed (server typecheck rejects them).
- **Client/server** (`docs/client-server.md` §6):
  - hydration is **client-owned**, not node-preserving (the region is cleared and
    re-rendered);
  - the client "entry" designation and the `ClientCode`/`IRequiresResources`
    pipeline are still minimal;
  - external JS libraries (`[<Require>]`/`IResourceDefinition`) are not
    injected: a binding lowers to a **global** (`new globalThis.Chart(…)`) but
    its `<script>` tag must be added by hand (`docs/client-bundle.md` §11);
  - cross-.NET-server interop would need a key + serialization contract independent
    of OCaml source positions.
- **Boundary wire form** (`docs/client-server.md` §3.2):
  - `int32`/`int64`/`nativeint` are rejected (no wire form);
  - OCaml objects/classes are not representable.
