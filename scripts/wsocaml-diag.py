#!/usr/bin/env python3
"""Normalize wsocaml build diagnostics to single-line `file:line:col:endCol: severity: msg`.

The OCaml frontend and ocamlc/ocamlopt emit the multi-line report

    File "<path>", lines <L>[-<L2>], characters <A>-<B>:
    <source line>            (ocamlc only)
    <caret>                  (ocamlc only)
    Error: <message...>
    <continuation lines...>
    Typecore.Error(_, _, _)   (frontend only)

which a VS Code problem matcher cannot consume directly. This rewrites each such
block to a single `path:L:A:B: error|warning: message` line (1-based columns,
continuations/hints joined). All other lines pass through unchanged.

Usage: <tool output> | wsocaml-diag.py
"""
import re
import sys

HEADER = re.compile(r'^File "(.+)", lines? (\d+)(?:-\d+)?, characters (\d+)(?:-(\d+))?:')
MESSAGE = re.compile(r'^(Error|Warning\s+\d+\s+\[[^\]]*\]|Warning):?\s?(.*)$')
EXCEPTION = re.compile(r'^[A-Z][A-Za-z0-9_]*\.[A-Za-z_]+\([^)]*\)\s*$')


def severity(text: str) -> str:
    return "warning" if text.startswith("Warning") else "error"


def main() -> int:
    out = []
    path = None
    line_no = col = endcol = None
    message = None

    def flush():
        nonlocal path, line_no, col, endcol, message
        if path is not None and message is not None:
            start = int(col) + 1
            end = int(endcol) + 1 if endcol else start + 1
            out.append(f"{path}:{line_no}:{start}:{end}: {severity(message)}: {message}".rstrip())
        path = line_no = col = endcol = message = None

    for raw in sys.stdin:
        text = raw.rstrip("\n")
        header = HEADER.match(text)
        if header:
            flush()
            path, line_no, col, endcol = header.group(1), header.group(2), header.group(3), header.group(4)
            continue
        if path is not None:
            if message is None:
                m = MESSAGE.match(text)
                if m:
                    message = m.group(2).strip()
                continue
            # indented lines and `Hint:` lines continue the message
            if (text[:1] in (" ", "\t") or text.startswith("Hint:")) and not EXCEPTION.match(text.strip()):
                message = (message + " " + text.strip()).strip()
                continue
            flush()
        if not EXCEPTION.match(text):
            out.append(text)
    flush()

    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
