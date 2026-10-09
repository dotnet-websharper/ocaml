#!/usr/bin/env bash
# Build the example to JavaScript via the WebSharper.UI A'' pipeline.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
bash "$root/scripts/build-ui-app.sh" "$here/dom.ml" "${1:-out}"
