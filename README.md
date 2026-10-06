# wsocaml Lambda prototype

This revision uses OCaml's own executable lowering instead of serializing `Typedtree` patterns:

`Parse -> Typemod.type_structure -> Translmod.transl_implementation -> Lambda.program -> wsocaml-ir-3 -> WebSharper AST -> JavaScript`

This removes the OCaml 5.4 `Tpat_value`/computation-pattern GADT boundary from wsocaml.

## Build

Frontend (OCaml 5.4.1):

    cd frontend
    opam install dune yojson
    dune build

Backend:

    cd backend
    dotnet restore
    dotnet build

## Frontend

    dune exec wsocaml-frontend -- --input ../examples/hello/hello.ml --output hello.wsir.json

## Backend

    dotnet run --project backend/WebSharper.OCaml.fsproj -- --ir frontend/hello.wsir.json --output out

## Status

This is still a compiler prototype, not a complete OCaml implementation. OCaml itself now handles typing and pattern-match compilation. The Lambda serializer covers the core Lambda forms and a useful primitive subset; unsupported runtime primitives, objects, static catches and exceptions fail explicitly. The backend consumes `wsocaml-ir-3` directly and lowers it to WebSharper AST.
