# Client JS output — layout and loading (no bundler)

Why a wsocaml app's browser bundle can `import` WebSharper libraries without a
bundler like Vite/esbuild/Webpack: the output is **native ES modules**, the
WebSharper library modules are **pre-generated as individual ESM files** by
WebSharper's own packager, and the **OCaml server also serves them statically**.

Related: [`client-server.md`](client-server.md) (tier split),
[`hydrate-client.md`](hydrate-client.md) (the hydration runtime),
[`codegen.md`](codegen.md) (`server.ml`). The backend side is
`backend/Program.fs`; line numbers drift.

## 1. Layout

A clean `bash examples/hello-world/build.sh <out>` produces
(`<out>/client` is the browser bundle; `<out>/server` is the native binary):

```
<out>/client/
  Main.js                        # the entry module (export default …)
  Main.wsir.json                 # the IR it was produced from (kept for reference)
  package.json                   # { "type": "module" }
  WebSharper.UI/                 # ~124 ES modules, one per WebSharper class
    WebSharper.UI.Doc.js
    WebSharper.UI.Var.js
    WebSharper.UI.Attr.js
    …
  WebSharper.StdLib/             # FSharpList, SeqModule, Option, … (one per class)
  WebSharper.JavaScript/         # present, may be empty (nothing referenced from it)
  WebSharper.Core.JavaScript/
    Runtime.js                   # the WebSharper JS runtime
  Stdlib.js  Stdlib__List.js …   # OCaml-stdlib shim modules (copied, see §7)
```

`<out>/` also holds `server.ml` + the compiled `server` (and `.deps/`, the
`build-ui-app.sh` scratch dir).

## 2. The entry is plain ESM

`scripts/build-ui-app.sh` writes `{"type":"module"}` (`:68`); `Main.js` uses
`import`/`export` and a `globalThis.OCamlRuntime.registerClient(…)` tail:

```js
import d from "./WebSharper.UI/WebSharper.UI.Var.js"
import { Some as e } from "./WebSharper.StdLib/Microsoft.FSharp.Core.FSharpOption`1.js"
import { GetOrLoadTemplate as f } from "./WebSharper.UI/WebSharper.UI.Client.Templates.js"
import { ParseHTMLIntoFakeRoot as g } from "./WebSharper.UI/WebSharper.UI.DomUtility.js"
import h from "./WebSharper.UI/WebSharper.UI.TemplateHoleModule.Text.js"
import i from "./WebSharper.UI/WebSharper.UI.TemplateHoleModule.Event.js"
import j from "./WebSharper.UI/WebSharper.UI.TemplateHoleModule.VarFloatUnchecked.js"
import k from "./WebSharper.UI/WebSharper.UI.Doc.js"
…
export default a;
globalThis.OCamlRuntime.registerClient("ws718983249", a[2]);
```

Every specifier is a **relative file path** — there are no bare specifiers
(`import … from "websharper-ui"`) and no `node_modules`. That is the whole
trick: relative specifiers resolve on the filesystem, so the browser's module
loader needs no resolver plugin.

## 3. Where the WebSharper library modules come from

When `--ws-compile` is given references (`WebSharper.UI.dll`,
`WebSharper.StdLib.dll`, `WebSharper.JavaScript.dll`), the backend runs
WebSharper's packager over their **metadata** and writes the modules itself —
`packageReferences` (`backend/Program.fs:41`, called at `:190`):

1. each `--reference` assembly is loaded and its WebSharper metadata read
   (`loadInfo`, `:33`);
2. `JavaScriptPackager.packageAssembly … EntryPointStyle.LibraryBundle` (`:62`)
   is run per assembly;
3. each resulting module is written to `<output>/<AssemblyName>/<Type>.js`
   (`:72`);
4. the runtime is extracted from the `WebSharper.Core.JavaScript` assembly's
   `WebSharper.Core.JavaScript.Runtime.js` manifest resource and written to
   `<output>/WebSharper.Core.JavaScript/Runtime.js` (`:76-82`).

The per-class modules are themselves ESM with the same relative-import shape,
e.g. `WebSharper.UI/WebSharper.UI.Doc.js`:

```js
import b from "../WebSharper.StdLib/System.Object.js"
import c from "./WebSharper.UI.Attr.js"
import { MarkResizable as k, Lazy as l } from "../WebSharper.Core.JavaScript/Runtime.js"
import { Map as o, … } from "./WebSharper.UI.View.js"
…
```

So WebSharper's packager fills the bundler's role — except instead of
concatenating, it **emits the dependency graph as individual files**.

## 4. How the imports resolve

The app file's calls into the referenced assemblies are lowered to WebSharper
nodes and then, via `Translator.DotNetToJavaScript.CompileFull` +
`JavaScriptPackager.packageAssembly … RequiredEntryPoint`, written out with
`ctx.Comp.AssemblyName <- "."` (`Program.fs:161`). That makes the writer emit
imports as `./<Assembly>/<Class>.js` relative to the entry file (`././` is
collapsed to `./`, `:185`). The referenced-assembly modules from §3 are exactly
the files those specifiers name — the graph is complete by construction.

The entry file itself is written from the packager result (`$EntryPoint` →
`Main.js`, others → `<name>.js`, `:187`).

## 5. How it is served

`examples/hello-world/build.sh` passes `--static <out>/client`, so `server.ml`
runs `WebSharper_Server.Server.serve ~port:8123 ~bundle:"Main" ~static:"…"`.
`Server.serve` (`runtimes/ocaml/webSharper_Server.ml`) injects the entry script
into the page (`replace_scripts`, `:88`):

```html
<script type="module" src="/Main.js"></script>
```

and, for requests its sitelet does not route, falls back to
`serve_file dir path` (`:137`), which maps `.js` → `text/javascript;
charset=utf-8` (`content_type_of`, `:110`). The browser then fetches the
transitive imports over HTTP as ordinary modules:

```
GET /Main.js                                200 text/javascript
GET /WebSharper.UI/WebSharper.UI.Doc.js     200 text/javascript
GET /WebSharper.Core.JavaScript/Runtime.js  200 text/javascript
GET /package.json                           200 application/json
```

Correct `Content-Type` matters: a module fetched as `application/octet-stream`
is refused by the browser. The OCaml server sets it for you.

## 6. The `OCamlRuntime` prelude

`runtimePrelude()` reads the embedded `wsocaml-runtime.js` resource
(`Program.fs:23`) and is prepended to the entry file when the program uses the
runtime (`:186`), guarded so it installs once:

```js
if (!globalThis.OCamlRuntime) { (function () { … })(); }
```

The WS library modules call into `globalThis.OCamlRuntime` (closures, apply,
marshalling), so it must exist before the module bodies run.

## 7. The `Stdlib*` shims

The bare `Stdlib.js` / `Stdlib__List.js` / … are the OCaml-standard-library
shim modules (committed under `backend/tests/Stdlib*.js`; the frontend's
`gen_stdlib_shim.ml` / `stdlib_shims_data.ml` is their source of truth). When the
IR's `requiredGlobals` includes an OCaml unit, the backend adds an import for it
(`Program.fs:731`), so `Main.js` can end up with e.g. `import … from
"./Stdlib__List.js"`. `build-ui-app.sh` copies the shims next to the entry
(`:63`). hello-world happens not to need any.

## 8. Why no bundler — and when you would add one

A bundler (Vite/esbuild/Webpack) normally earns its place by:

- resolving **bare** specifiers / `node_modules`;
- transpiling TS/JSX/next-gen syntax;
- collapsing many modules into fewer requests.

Here none applies: the OCaml → WebSharper frontend already produced plain JS,
every specifier is a relative path that exists on disk, and the WebSharper
packager already emitted the graph. So the native module loader is enough.

The tradeoff is **request count**: ~124 files just under `WebSharper.UI/` alone.
The browser fetches them in parallel, which is fine over localhost for a
demo/example; for production you would pipe `<out>/client` through a bundler (or
a CDN with HTTP/2) to collapse them.

## 9. Edge cases / notes

- **No references ⇒ no packaging.** The `references.Count > 0 && wsCompile`
  branch (`Program.fs:156`) takes the packager path; otherwise the backend emits
  a single self-contained file with no imports (`:191`, `:202`) — that is the
  plain `backend/tests/cases/` path.
- **`--package-references` is currently a no-op.** It is parsed (`:106`) but
  ignored (`:214`); packaging runs in the `--ws-compile` + `--reference` branch
  regardless.
- **A `<Assembly>/` dir can be empty** (e.g. `WebSharper.JavaScript/` in
  hello-world) — the packager only emits classes that are actually referenced.
- **`<unit>.server.js`** is a separate, server-side bundle emitted when the IR
  has `[@rpc]`/server-only bodies (`writeServerBundle`, `:146`); it is not part
  of the browser graph.
- **Stale files persist.** `build.sh` writes into `<out>/client` without
  cleaning, so a leftover from an earlier tool can linger (that is how a stray
  `WebSharper_UI__Template.js`, not referenced by `Main.js`, survives in a
  previously-used `out/`).

## 10. Tests / related

- Layout producer: `backend/Program.fs` (`packageReferences`, `runtimePrelude`,
  the `wsCompile` branch).
- Bundle writer: `scripts/build-ui-app.sh` (`package.json`, shim copy).
- Server static host: `runtimes/ocaml/webSharper_Server.ml`
  (`replace_scripts`, `serve_file`, `content_type_of`).
- Example: `examples/hello-world/build.sh`, `run.sh`.
- Raw-FFI fixture (the external-global case): `bindings-legacy/`,
  `frontend/bin/gen_bindings.ml`, `scripts/build-js-app.sh`,
  `backend/tests/apps/jsbind.ml` + `jsbind.out`, `backend/tests/apps/dom.ml` +
  `dom.mjs` + `dom.out`.
- README §"Packaging referenced assemblies" is the short version of §3.

## 11. External JS libraries (Chart.js, etc.)

A binding to a non-WebSharper library (Chart.js, D3, …) is expressed as access to
a **browser global**, not an ES import, so it works **without a bundler** —
provided the library is loaded as a global script. wsocaml does **not** inject
that script for you.

### How such a binding lowers

The raw-FFI schemes (`bindings-legacy/`, `frontend/bin/gen_bindings.ml`) parse a
dotted path into a global address and emit `globalThis.<Name>`
(`backend/Lowering.fs:424-441`):

```ocaml
external max    : float -> float -> float = "js:Math.max"    (* Console/Math *)
external create : unit -> t =                "jsnew0:Date"   (* JsDate *)
external now    : unit -> float =            "js0:Date.now"
```

lowers to:

```js
globalThis.Math.max(3, 8)
new globalThis.Date()
```

A hand-written WebSharper binding using `[<Stub>]` / `[<Name "Chart">]` /
`[<Inline "$globalThis.Chart…">]` also ends up naming the global.

For Chart.js the emitted call is `new globalThis.Chart(canvas, cfg)`, and there is
**no `import … from "chart.js"`**: Chart.js is not a `--reference` WebSharper
assembly, so `packageReferences` (§3) emits nothing for it. The binding *module*
(`Chart.js` in `out/client/`) is emitted and imported relatively like any other
unit (§2–§4) — but it only *references* `globalThis.Chart`.

### What you must do: load the global

`runtimes/ocaml/webSharper_Server.ml` is a minimal page renderer; it does not
process `[<Require>]`/`IResourceDefinition`, so a binding's declared script
dependency is **not** auto-injected (see the gap below). Add the tag yourself —
`Content.page` takes a raw `~head`:

```ocaml
Content.page
  ~title:"Chart demo"
  ~head:"<script src=\"https://cdn.jsdelivr.net/npm/chart.js@4\"></script>"
  [ hydrate (fun () -> … new Chart(canvas, cfg) …) ]
```

or serve a local copy from the `--static` dir and point the tag at `/<file>.js`.

The `dom.ml` test shows the same pattern under jsdom:
`backend/tests/apps/dom.mjs` sets `globalThis.window`/`globalThis.document` before
importing `Main.js`; for a chart test you would likewise provide
`globalThis.Chart` (a loaded CDN script, or `require`'d in the driver).

**Load order.** A classic (non-module) `<script src>` in `<head>` runs before the
deferred `<script type="module" src="/Main.js">`, so the global is in place by the
time the bundle executes. If you load the library as a *module* instead, make sure
it runs first, or assign the global from a module that `Main.js` imports.

### Binding styles and the bundler question

| binding style | emitted | runs without a bundler? | you must |
| --- | --- | --- | --- |
| raw FFI / WS stub → global (`jsnew:Chart`) | `new globalThis.Chart(…)` | ✅ | add a `<script src=…>` (CDN or `--static`) |
| `[<Import>]` with a **URL** specifier | `import … from "https://…"` | ✅ (if supported) | nothing |
| `[<Import>]` with a **bare** specifier | `import … from "chart.js"` | ❌ | an import map, or a bundler |

### The ESM alternative — the one case that needs a bundler

WebSharper's `[<Import("Chart", "chart.js")>]` makes the packager emit
`import { Chart } from "chart.js"`. If the specifier is **bare**, the browser
cannot resolve it (that is Node/npm resolution, which only a bundler or an
`<script type="importmap">` provides):

```html
<script type="importmap">
{ "imports": { "chart.js": "https://cdn.jsdelivr.net/npm/chart.js@4/+esm" } }
</script>
```

A **URL** specifier needs no map and loads natively.

Neither `binding-adaptor` nor `Lowering.fs` models `[<Import>]`/`[<Require>]`
today (no handling to be found), so the **global route above is the supported
one**. The intended fix is to honour `[<Require>]`/`IResourceDefinition`
(render the scripts into the page) and/or `[<Import>]` (emit the specifier);
that is tracked in `WIP.md`.

### `[<Require>]` / resources: not implemented

WebSharper resources (`[<Require(typeof<…>)>]` where the type implements
`IResourceDefinition`) are how .NET WebSharper renders an external library's
`<script>`/`<link>` into the page automatically, and they also participate in
the `IRequiresResources`/`ClientCode` pipeline. wsocaml reimplements the server
minimally and none of that is wired — deferred per `docs/client-server.md` §6.
So an external-lib binding compiles and lowers correctly, but **silently misses
its script tag** unless you provide it (`~head`, `--static` + a tag, or a
`<script>` in the page/template).
