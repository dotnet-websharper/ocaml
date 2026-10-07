#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
bash "$root/scripts/build-ws-module.sh" "$here/test.ml" Test "${1:-out}"
bash "$root/scripts/build-ws-module.sh" "$here/du.ml" Du "${1:-out}"
