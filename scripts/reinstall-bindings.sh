#!/usr/bin/env bash
# Install the generated binding packages from ./bindings after regenerating them
# with binding-adaptor (see AGENTS.md, "Regenerating generated things").
#
#   dotnet binding-adaptor/bin/Debug/net10.0/binding-adaptor.dll gen … --dest ./bindings
#   scripts/reinstall-bindings.sh
#
# `opam update wsocaml` is required: without it `opam reinstall` rebuilds from the
# *previously published* tarball of the local repo, so the installed .ml/.cmi
# silently stay stale (the frontend, `dune` and the app scripts consume the
# installed copies, never ./bindings directly).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(opam env)"

opam update wsocaml
opam reinstall \
  websharper-javascript websharper-stdlib websharper-sitelets \
  websharper-ui websharper-ui-templating-runtime websharper-ui-server \
  -y

cat <<'EOF'
Reinstalled the generated bindings.
Next:
  - re-run the suite:            bash backend/tests/run-tests.sh
  - rebuild the examples:        bash examples/<name>/build.sh <out>
  - (edited a *shadow* in runtimes/ui-server? it is reinstalled above as
    websharper-ui-server, which is what `dune build`/`build.sh` typecheck against)
EOF
