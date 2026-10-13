#!/usr/bin/env bash
# Build and run the hello-world server.
#   bash run.sh        # builds, then serves on http://127.0.0.1:8123/
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/build.sh"
echo "serving on http://127.0.0.1:8123/ (Ctrl-C to stop)"
exec "$here/out/server"
