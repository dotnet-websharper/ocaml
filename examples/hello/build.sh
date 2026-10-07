#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
bash "$root/scripts/build-ws-module.sh" "$here/hello.ml" Hello "${1:-out}"
