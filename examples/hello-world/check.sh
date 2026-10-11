#!/usr/bin/env bash
# Build the app and emit single-line diagnostics (file:line:col: severity: msg)
# for the VS Code problem matcher in .vscode/tasks.json.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
bash "$here/build.sh" 2>&1 | python3 "$root/scripts/wsocaml-diag.py"
