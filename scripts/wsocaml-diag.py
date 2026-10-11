#!/usr/bin/env python3
"""Normalize wsocaml build diagnostics to single-line `file:line:col: severity: msg`.

The OCaml frontend and ocamlc/ocamlopt emit the multi-line report

    File "<path>", line <L>, characters <A>-<B>:
    <source line>            (ocamlc only)
    <caret>                  (ocamlc only)
    Error: <message...>
    <continuation lines...>
    Typecore.Error(_, _, _)   (frontend only)

which a VS Code problem matcher cannot consume directly. This rewrites each such
block to a single `path:L:A: error|warning: message` line (continuations joined).
All other lines pass through unchanged (e.g. dotnet/FS errors already single-line).

Usage: <tool output> | wsocaml-diag.py
"""
import re
import sys

HEADER = re.compile(r'^File "(.+)", line (\d+), characters (\d+)-\d+:')
MESSAGE = re.compile(r'^(Error|Warning\s+\d+\s+\[[^\]]*\]|Warning):?\s?(.*)$')
EXCEPTION = re.compile(r'^[A-Z][A-Za-z0-9_]*\.[A-Za-z_]+\([^)]*\)\s*$')


def severity(text: str) -> str:
    return "warning" if text.startswith("Warning") else "error"


def main() -> int:
    out = []
    path = line_no = col = None
    message = None  # None until we see the Error/Warning line

    def flush():
        nonlocal path, line_no, col, message
        if path is not None and message is not None:
            out.append(f"{path}:{line_no}:{col}: {severity(message)}: {message}".rstrip())
        path = line_no = col = message = None

    for raw in sys.stdin:
        text = raw.rstrip("\n")
        header = HEADER.match(text)
        if header:
            flush()
            path, line_no, col = header.group(1), header.group(2), header.group(3)
            continue
        if path is not None:
            if message is None:
                m = MESSAGE.match(text)
                if m:
                    message = m.group(2).strip()
                # else: source/caret excerpt -> skip
                continue
            # after the message: indented lines continue it
            if text[:1] in (" ", "\t") and not EXCEPTION.match(text.strip()):
                message = (message + " " + text.strip()).strip()
                continue
            flush()
            # fall through and handle this line normally
        if not EXCEPTION.match(text):
            out.append(text)
    flush()

    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
