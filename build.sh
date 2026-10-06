#!/usr/bin/env sh
set -eu
(cd frontend && dune build)
(cd backend && dotnet build -c Release)
echo "Build complete."
