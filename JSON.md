# JSON / RPC marshalling — why it's hand-rolled, and what adopting WebSharper's JSON would take

*Status: design note + roadmap. The short version of §2 lives in
`docs/client-server.md` §3.2; this file is the long form (why, what adopting
WebSharper's JSON would take, and the alternatives).*

The RPC/`[@export]` boundary carries values between an **OCaml client compiled to
JS** (frontend → `.wsir.json` IR → F# backend → WebSharper packager) and a
**native OCaml server** (`--emit-server` → `server.ml` → `ocamlfind`/`ocamlopt` +
`yojson`). There is no .NET assembly and no WebSharper runtime on the server side.

---

## 1. Where marshalling lives today

The wire format is **already WebSharper's external representation**; what is ours
is the code that applies it on each tier.

| OCaml value | external (JS / JSON) |
| --- | --- |
| `int` / `float` | number |
| `bool` | boolean |
| `string` | string |
| `char` | 1-char string |
| `unit` | `null` |
| `list` / `array` | array |
| `option` | `None` → `null`, `Some x` → `x` |
| tuple | array `[a, b]` |
| record | object `{ x, y }` (field names) |
| variant | `{"$":"Case","$0":a,…}`; constants `{"$":"Case"}` |

Three artifacts implement it:

| Artifact | Role | Where |
| --- | --- | --- |
| generated **native** `toJson_*` / `ofJson_*` (`yojson`) | the server half | `frontend/bin/main.ml` (`enc` / `dec` / `helperDefs`, emitted into `server.ml`; `Wsrpc.register` in `runtimes/ocaml/wsrpc.ml`) |
| the unit's **named type declarations** (`UnitIR.Types`) | the shared type model | `frontend/bin/main.ml` (`typeId` / `descr` / `unitTypes`; IR `types`) |
| a compact **type descriptor** per rpc/export, embedded in the IR | describes the payload shape to the client | `frontend/bin/main.ml` (`descr`; IR `rpcs` / `exports`) |
| the **client marshaller** — descriptor interpreter | the client half | `backend/Runtime.js` (`registerTypes` / `resolveType` / `marshalIn` / `marshalOut` / `rpcMeta`, driving `rpcCall`, `exported`, `registerRpc`) |

Named records/variants are declared **once per unit** (`types`, keyed by a stable
id) and referenced by id from the per-entry descriptors; the runtime registers
them at module init (`OCamlRuntime.registerTypes([…])`) and resolves ids from that
registry. `UnitIR` (`backend/Ir.fs`) is otherwise a lowered lambda `Code` plus
`Rpcs` / `Exports` / `Clients`. Descriptors from `wsocaml-ir-4`/`5` still carry
their own `types` array with `key` references and are resolved from it.

---

## 2. Why not WebSharper's built-in JSON (short form)

1. **The peer is native OCaml.** `WebSharper.Core.Json` / `WebSharper.Json` are
   .NET/JS-side; the server is `yojson` with no WebSharper runtime. An
   encoder/decoder must exist natively regardless, so delegating the client half
   just creates two serializers that have to agree byte-for-byte.
2. **wsocaml types carry no WebSharper metadata.** WS's JSON is metadata-driven
   (see §3). The backend never *mints* `TypeDefinition`s; OCaml records/variants
   lower to plain JS blocks (`{ $tag: 0, "0": … }`, `backend/Lowering.fs`). Only
   the `--reference` assemblies have metadata (`backend/Bindings.fs`,
   `IO.LoadMetadata`).
3. **The client's in-memory values are the OCaml runtime representation**, not
   WebSharper's (§4), so a representation→representation bridge is needed before
   *any* serializer. That bridge is exactly `marshalIn` / `marshalOut`.
4. **The built-in JS JSON is used where it applies**: the envelope
   (`JSON.stringify` / `JSON.parse`) and the descriptors.
5. The same external shape also serves **`[@export]` consumers that are plain
   JS**, which a typed serializer does not address.

So `Runtime.js`'s marshaller is our `Json.Activate`; the generated native codecs
are the other language's serializer. Neither is a substitute for the other.

---

## 3. What WS's machinery actually is

Not a runtime schema walk — **compile-time `System.Type` reflection**:

- `WebSharper.Core.Json.Provider(fo).GetEncoder / GetDecoder(System.Type)` is a
  reflection-based encoder/decoder over a JSON `Value` AST (`Json.fs`,
  `Provider` / `Serializer` / `FormatSettings`).
- Client-side typed JSON is the **`WebSharper.TypedJson.Encode / Decode<'T>`
  macro**, driven by the compiler's `compileDeserializers` loop over
  `comp.TypesNeedingDeserialization`: for each type it emits a call
  `TypedJson.Decode< t >` and translates it, producing per-type JS through the
  `WebSharper.Web.ClientSideJson.Provider` combinators (`EncodeRecord`,
  `EncodeUnion`, `EncodeList`, `EncodeDateTime`, …), then caches the result in
  metadata as `AddJsonMetadataEntry(…, JsonSerializer(td, method))`
  (`Translator.fs`).
- `JsonSerializerEntry = JsonId | JsonSerializer of TypeDefinition * Method`.
  **`JsonId` = identity**: the runtime representation already *is* the JSON
  representation, so no code is generated (a very useful fast path).
- Precompiled assemblies are reflectable because metadata carries
  **`CustomTypeInfo`** — a serialized CLR reflection blob:
  `FSharpRecordInfo of FSharpRecordFieldInfo list`,
  `FSharpUnionInfo of FSharpUnionInfo`, `FSharpUnionCaseInfo`, `EnumInfo`,
  `StructInfo`, `DelegateInfo`, `FSharpAnonRecordInfo`, `NotCustomType`
  (`Metadata.fs`). It is reached through `ICompilation.GetCustomTypeInfo`.
- The generated code reads/writes the **WebSharper runtime representation**, not
  ours (§4).

Consequence: "use WS's JSON" means *synthesize .NET-style type info for OCaml
types* and either match WS's runtime representation or override the serializer
per type.

---

## 4. Representation delta

WebSharper's client JSON combinators operate on WS's runtime shapes; ours are the
OCaml runtime shapes emulated by `backend/Runtime.js`.

| Value | WebSharper (`ClientSideJson.fs`) | wsocaml (`Lowering.fs`, `Runtime.js`) |
| --- | --- | --- |
| variant | `{ $: <numeric tag index>, "0": arg }` (`DecodeUnion` writes `o.$`, `EncodeUnion` indexes `cases` by `x.$`) | `{ $tag: <numeric>, "0": arg }` |
| record | object with **named** fields (`x?name`) | positional block `{ $tag:0, "0":…, "1":… }` |
| `list<'T>` | JS array (`EncodeList` builds `obj[]`, `DecodeList` runs on `obj[]`) | cons cells `{ $tag:0, "0":h, "1":t }` |
| `option` | value or absent/null (`NormalOption` / `MarkedOption` / `ErasedOption` field kinds) | `0` / `{ $tag:0, "0":x }` |
| constant DU case | boxed name/number (`[<Constant>]`) | immediate integer tag |

The **wire** format already agrees; the **in-memory** shapes do not.

---

## 5. What's needed

### Phase 0 — named type declarations in the IR  *(done)*

**What it was.** The frontend already emitted named declarations, but *per
rpc/export*: `rpcMeta` created a fresh `defs` table per entry and inlined
`{"types":[…],"args":…,"result":…}` as a JSON string in `rpcs[i].meta`, with
`{"k":"named","key":…}` references whose key was a frontend-minted `instKey`
(`point`, `tree_int`) — unit-local, collision-prone, and repeated in every entry
that used it (and therefore in every emitted bundle, since `Lowering.fs` writes
the meta as a JS string literal).

**What it is now.** One *unit-level* `types` section, keyed by a stable `typeId`
(`<unit>.<path>` plus the instantiation, e.g. `Main.point`, `Main.tree<int>`);
per-entry descriptors reference it by id and carry no `types` of their own. The
backend emits `OCamlRuntime.registerTypes([…])` once at module init
(`Lowering.typeRegs`), and the runtime resolves ids from that registry. Descriptors
from older IRs still resolve their own `types`/`key`s, so `wsocaml-ir-4`/`5`
fixtures (notably the committed `backend/tests/cases/*.wsir.json`, which nothing
regenerates) keep working unchanged.

**Gets us** (measured):
- **dedup.** A declaration shared by N rpcs/exports is emitted once instead of N
  times. For `backend/tests/apps-ws/wsdata.ml` (7 rpcs, 3 declarations) descriptor
  bytes drop 15 %; a synthetic 11-rpc app over one 8-field record drops 73 %.
- **one type model.** The declaration list can now drive `descr`, the native
  `yojson` codecs (`enc`/`dec`/`helperDefs`), the `.d.ts` emitter (`dtsType`) and
  the runtime marshaller. Today those are four independent walks of the same type
  information.
- **stable identity.** Unit-qualified, so the same type name in two units cannot
  collide, and carryable across units — required by Phase 1 and by any cross-unit
  or shared emission.
- **better diagnostics.** One validation point that can name a real type with a
  location instead of reporting a mangled `instKey`.
- **a home for flags.** Exactly the ones `CustomTypeInfo` needs (field
  optionality, union case names/discriminator, `DateTime` format,
  `[<Constant>]`), so Phase 1's minting becomes a projection rather than a second,
  parallel model.
- it is the enabling step for **two of the three** §7 paths (Phase 1, and the
  "generate the client codecs" route). The *capability* hybrid needs almost none
  of it — see §7.

**Still missing after Phase 0:**
- **no behaviour change.** Same wire format, same supported payload types;
  `DateTime`, `Map`/`Set`, boxed ints and bound WS types are still rejected.
- **still no WebSharper metadata.** No `CustomTypeInfo`, so `Json.Provider` and
  `TypedJson` remain unreachable — Phases 1–2 are still ahead.
- **the marshaller still exists**, now reading a hoisted registry instead of a
  per-entry one — Phase 5 is still ahead.
- **the native codecs are still a second implementation**, so the Phase 4
  conformance suite is still required.
- **the representation delta (§4) is untouched**, so the Phase 3 fork (and its
  cost) is unchanged.
- **`--ws-compile` visibility** (§8) is still unanswered; Phase 0 does not touch
  `Program.fs` / `Bindings.fs`.
- it **forces a decision** that can constrain Phase 1: one declaration per
  concrete instantiation (what we do) vs a generic declaration with parameters,
  which is what a closed .NET `CustomTypeInfo` would want.

**Cost / risk.** Additive and near golden-neutral: older IRs keep working, the
frontend's other type walks are untouched, and the only emitted-JS change is the
runtime prelude plus `registerTypes` when a unit has declarations. One
**non-Phase-0 bug** it surfaced and fixed in the same change: `marshalOut` did not
separate constant from non-constant variant tags (the two tag spaces are numbered
independently), so an rpc *result* whose variant had both kinds silently decoded
to the constant case (`type shape = Dot | Circle of int` sent `Circle 5` as
`Dot`). Regression coverage: `backend/tests/apps-ws/wsdata.mjs` and
`scripts/rpc-data.sh` now drive the *generated* proxies for records, variants,
tuples, lists, options and arrays — in-process, and over HTTP against the native
server so the native codecs are on the other side of the wire.

### Phase 1 — mint `TypeDefinition` + `CustomTypeInfo`  *(L)*
For each declaration: build `ConcreteType`/`TypeDefinition`, a `TypeInfo`, and a
`CustomTypeInfo` (`FSharpRecordInfo` / `FSharpUnionInfo` / `EnumInfo`), and
register them on `ctx.Comp` (`backend/Program.fs` builds the `Compilation`;
`backend/Bindings.fs` holds `Comp`) so `ToCurrentMetadata()` and
`ICompilation.GetCustomTypeInfo` return them.
Acceptance: `GetCustomTypeInfo` returns a record/union for a hand-written test
type, and the metadata survives `--ws-compile`.

### Phase 2 — drive the JSON codegen  *(M–L)*
Either replicate `Translator.compileDeserializers` (`NewGenerated` +
`AddGeneratedCode` + `AddJsonMetadataEntry`) or call the `ClientSideJson.Provider`
combinators directly from `Lowering.fs`. Note this must happen **in the backend**:
the compiler path constructs `Generic decodeMethod [t]` calls, and our `ws:`
call sites currently do not resolve generic type arguments
(`docs/ws-differences.md` §2).
Acceptance: emitted JS for `int`, a record and a variant, diffed against the
current marshaller on the same values.

### Phase 3 — the representation fork  *(M, or XL)*
- **(a) Re-lower the runtime representation** to WS's (`$` + named records, arrays
  for lists, …). Rejected: `backend/Runtime.js` emulates the OCaml runtime and
  every `Stdlib*` shim encodes OCaml blocks (`{ $tag:0, "0":h, "1":t }`); this is
  a rewrite of the whole backend runtime, and it would break OCaml semantics
  (pattern matching lowers to `$tag` checks, `Obj`-style introspection, tuples).
- **(b) Register per-type serializer methods** via
  `AddJsonMetadataEntry(…, JsonSerializer(td, method))` that operate on *our*
  representation. This is today's codegen again, wearing WS metadata.

### Phase 4 — native side + conformance  *(M)*
WS's JSON has no `ocamlopt`/`yojson` counterpart, so the generated native codecs
stay. With two independent implementations the encoding rules must be pinned: a
conformance harness that round-trips the same values through the client's WS JSON
and the native codecs, covering options-as-null, `result`, chars, floats, boxed
ints, `DateTime`/`DateTimeOffset`, `[<OptionalField>]`, `[<NamedUnionCases>]`,
`EmptyUnionCaseName`, `[<Constant>]` cases.

### Phase 5 — cleanup  *(S)*
`Runtime.js`'s `marshalIn` / `marshalOut` shrink to the dynamic `[@export]` case;
the descriptor survives for name→type lookups and `.d.ts`.

---

## 6. Gains vs costs

Gains
- WS's encoding rules for free, including the ones we do not support at all:
  `DateTime`/`DateTimeOffset`, `BigInteger`, `Map`/`Set`/`Dictionary`,
  boxed ints, enums, `[<OptionalField>]`, `[<NamedUnionCases>]`.
- Interop with `WebSharper.Json` / Remoting / Sitelets clients and with
  precompiled WebSharper assemblies that already carry `CustomTypeInfo`
  (including binding-defined record types).
- `JsonId` fast path for types whose representation is already the JSON one.

Costs
- Phase 1–2 is deep backend work against an API designed for `System.Type`
  reflection, not for a synthetic type model.
- Phase 3 has no cheap branch: either an XL runtime-representation rewrite or (b),
  which is roughly today's marshaller under a new name.
- The native codecs and the descriptor do not go away.
- New coupling: the wire format becomes WS's JSON exactly, for every type.

---

## 7. Recommendation

- If the goal is **capability** (bound WS types, WS-interop), do the *hybrid*:
  keep the current wire format (it already equals WS's) and teach
  `descr` / `enc` / `dec` to consult the referenced assemblies' `CustomTypeInfo`
  for types that have metadata. Small, and it unblocks `DateTime`, `Map`, and
  binding-defined records without minting anything.
- If the goal is **less code**, generate the client codecs too from the same type
  walk (Phase 0), targeting `WebSharper_JavaScript.JSON` / plain objects, and
  delete the generic marshaller + descriptor interpreter. Keep `descr` only for
  the dynamic `[@export]` boundary. This removes the machinery that prompted the
  question and does not depend on WS's JSON at all.
- Full adoption (Phases 1–5) is only worth it if both are wanted, or if
  WebSharper-JSON-level interop is a hard requirement.

### What "gain" actually means for the scalar types

**Boundary types.** The .NET types WS's JSON has built-ins for are reachable
through the generated bindings — `websharper-stdlib` binds `System.DateTime`
(now `WebSharper_StdLib.DateTime`), `DateTimeOffset`, `TimeSpan`, `Guid`,
`BigInteger`, `Nullable<'T>`, `FSharpMap`/`FSharpSet`/`HashSet`/`ISet`,
`Dictionary`/`IList`/`IEnumerable`, and `websharper-javascript` adds the JS
`Date`/`BigInt`. There is **no binding** for `System.Uri`, `System.Decimal` or
`System.Numerics.Complex`, so those stay unreachable however the wire is done.

**OCaml counterparts.** Only the collection/option family has same-shaped OCaml
types (`option`, `list`, `array`, `Seq.t`, `Map.Make`, `Set.Make`, `Hashtbl`) —
and even there `Map`/`Set` are *functors*, not first-class generic types, so a
type-driven codec cannot be generic over the key type. The scalar types have
nothing in the stdlib: `DateTime`/`DateTimeOffset`/`TimeSpan` exist only as
`unix`'s `Unix.tm` + `float` (a server-only library) or as third-party
`ptime`/`timedesc`; `Guid` as `uuidm`; `BigInteger`/`decimal` as `zarith`. The
usable frontier is narrower still: the client tier ships only 14 `Stdlib__*`
shims (`Stdlib, Array, Buffer, Bytes, Char, Float, Hashtbl, Int, List, Option,
Printf, Result, String, Sys`), so `Map`/`Set`/`Int64` **typecheck and then fail at
runtime**, and a third-party library would have to compile to JS.

**Consequence.** Adopting WS's JSON buys the *serialization rules* for those
types, not new OCaml types. The sane shape is to keep the **WS binding type** as
the boundary type (that is what the JS APIs and the WS metadata speak) and
implement it natively behind a shadow with a representation of our choosing
(`Ptime.t`, `float` epoch, `int64` ms, …), matching WS's exact wire form
(ISO-8601 `toISOString`, ms number, `{d, o}`). The cheap alternative the tree
already uses is to keep time-like values as **strings** — `Hole.DateTime` (a
`ws-var` on `<input type="datetime-local">`) is generated as a `string` hole for
exactly this reason.

---

## 8. Open questions

- Does `--ws-compile` need the minted types to be visible to the *packager*
  (dead-code elimination / imports), or is registering them on the `Compilation`
  enough?
- Cross-unit identity: `instKey` (`tree_int`, `tup_int_string`) is not namespaced;
  minting needs a stable, collision-free scheme shared by every compiled unit.
- Recursive and generic types: WS's `CustomTypeInfo` describes a *closed* .NET
  type; our descriptors instantiate generics per concrete use. Does one minted
  type per instantiation suffice, and does that interact with `JsonId`?
- `result` and `FSharpOption` in a *top-level* position (WS handles option mostly
  as a field kind).
- Would adopting WS's shapes mean changing the *wire* too for edge cases we
  currently define ourselves (e.g. `char` as a 1-char string, unit as `null`)?

---

## Appendix A — file inventory

| File | Relevant part |
| --- | --- |
| `frontend/bin/main.ml` | `enc` / `dec` (native codecs), `descr` (IR descriptor), `helperDefs`, `emitServer` (registers `Wsrpc` handlers), `rpcs` / `exports` in the IR |
| `backend/Ir.fs` | `UnitIR` (`Rpcs`, `Exports`, `Code`) — no type declarations |
| `backend/Lowering.fs` | `lit` (`Block` → `$tag` block), variant tag checks, `RpcMeta`, `rpcCall` / `exported` / `registerRpc` emission |
| `backend/Program.fs` | `--ws-compile` path: `Compilation`, `CompileFull`, `ToCurrentMetadata`, `packageAssembly`, `packageReferences` |
| `backend/Bindings.fs` | `Context.Comp = Compilation(refMeta)`, `IO.LoadMetadata` over `--reference` assemblies |
| `backend/Runtime.js` | `marshalIn` / `marshalOut` / `rpcMeta`, `rpcCall`, `rpcTransport`, `exported`, `registerRpc` |
| `runtimes/ocaml/wsrpc.ml` | `Yojson`-based handler registry + HTTP server |
| `docs/client-server.md` §3.2 | external representation + the short "why not WS JSON" note |

## Appendix B — WebSharper sources consulted (core, `master`)

| Source | Used for |
| --- | --- |
| `src/compiler/WebSharper.Core/Json.fs` | `Provider.GetEncoder/GetDecoder(System.Type)`, `Serializer`, `FormatSettings` |
| `src/compiler/WebSharper.Core/Metadata.fs` | `CustomTypeInfo`, `FSharpRecordFieldInfo`, `FSharpUnionCaseInfo` / `FSharpUnionInfo`, `JsonSerializerEntry`, `ICompilation` |
| `src/compiler/WebSharper.Compiler/Translator.fs` | `compileDeserializers`, `TypesNeedingDeserialization`, `AddJsonMetadataEntry` |
| `src/sitelets/WebSharper.Web/ClientSideJson.fs` | `EncodeRecord` / `DecodeRecord` / `EncodeUnion` / `DecodeUnion` / `EncodeList`, `OptionalFieldKind` |
| `src/compiler/WebSharper.Core/TypedJson.fs` | `TypedJson.Encode/Decode/Serialize/Deserialize` |
