#!/usr/bin/env bash
# Build a wsocaml app that consumes the OCaml bindings in bindings/.
#   build-js-app.sh <entry.ml> [out-dir]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fe="$root/frontend/_build/default/bin/main.exe"
be="$root/backend/bin/Debug/net10.0/WebSharper.OCaml.dll"
s="$(ocamlc -where)"
bdir="$root/bindings"
entry="$1"
out="${2:-$root/out}"
mkdir -p "$out"

# dependency order (module names, capitalized)
order="Js Event UiEvent MouseEvent WheelEvent PointerEvent DragEvent TouchEvent
InputEvent CompositionEvent KeyboardEvent FocusEvent MessageEvent ProgressEvent
SubmitEvent CustomEvent ErrorEvent PopStateEvent HashChangeEvent StorageEvent
BeforeUnloadEvent AbortSignal AbortController DomRectReadOnly DomRect DomPoint
DomMatrix Node Element DomTokenList CssStyle Text Comment Attr NodeList
HtmlCollection DocumentFragment Location Json JsDate RegExp Promise JsError
JsObject JsArray JsMap JsSet WeakMap WeakSet JsSymbol Headers UrlSearchParams Url
CanvasGradient CanvasPattern ImageData TextMetrics Path2D CanvasRenderingContext2D
OffscreenCanvas Storage Crypto TextEncoder TextDecoder Blob File FileList
FileReader FormData Request Response XmlHttpRequest WebSocket EventSource
MessagePort MessageChannel BroadcastChannel Worker MediaDevices Permissions
StorageManager MediaStreamTrack MediaStream AudioParam AudioNode GainNode
OscillatorNode AudioBuffer AudioBufferSourceNode AudioContext
IntlDateTimeFormat IntlNumberFormat IntlCollator Notification
PerformanceObserver MutationObserver IntersectionObserver ResizeObserver Selection
HtmlElement HtmlAnchorElement HtmlButtonElement HtmlTextAreaElement HtmlFormElement
HtmlSelectElement HtmlOptionElement HtmlOptGroupElement HtmlLabelElement
HtmlMediaElement HtmlVideoElement HtmlAudioElement HtmlSourceElement
HtmlTableElement HtmlTableRowElement HtmlTableCellElement HtmlIFrameElement
HtmlScriptElement HtmlStyleElement HtmlLinkElement HtmlMetaElement
HtmlTitleElement HtmlTemplateElement HtmlDialogElement HtmlDetailsElement
HtmlProgressElement HtmlDivElement HtmlInputElement HtmlCanvasElement
HtmlImageElement Navigator History Screen Performance Document Console Window
Math JsGlobal Timers"
base_of() { echo "$(echo "${1:0:1}" | tr 'A-Z' 'a-z')${1:1}"; }

# 1) type-check bindings -> .cmi
for m in $order; do
  f="$bdir/$(base_of "$m").ml"
  [ -f "$f" ] || continue
  (cd "$bdir" && ocamlc -c -I "$s" "$(basename "$f")")
done

# 2) compile bindings -> .js
for m in $order; do
  f="$bdir/$(base_of "$m").ml"
  [ -f "$f" ] || continue
  "$fe" --input "$f" --output "$out/$(base_of "$m").wsir.json" --unit "$m" -I "$bdir" -I "$s"
  dotnet "$be" --ir "$out/$(base_of "$m").wsir.json" --output "$out" --compact
done

# 3) compile entry -> .js
"$fe" --input "$entry" --output "$out/main.wsir.json" --unit Main -I "$bdir" -I "$s"
dotnet "$be" --ir "$out/main.wsir.json" --output "$out" --compact

# 4) link stdlib shims + package.json
cp "$root/backend/tests/Stdlib"*.js "$out/"
printf '{ "type": "module" }\n' > "$out/package.json"
echo "built $out/Main.js"
