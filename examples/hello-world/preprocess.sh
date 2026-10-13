#!/usr/bin/env bash
# Expand `[%template "..."]` in a source file for the editor (dune preprocess).
# The frontend is invoked with `--preprocess`; its stdout is the expanded source.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
exec "$root/frontend/_build/default/bin/main.exe" --preprocess --input "$1"
