#!/usr/bin/env python3
"""
Strip ANSI escape sequences and control codes from a log stream.

Usage:
  codex_log_clean.py -i INPUT [-o OUTPUT]
  codex_log_clean.py < INPUT > OUTPUT
"""

from __future__ import annotations

import argparse
import sys
from typing import Optional


ESC = 0x1B
BEL = 0x07


def _strip_ansi_bytes(data: bytes) -> str:
    """Remove ANSI escape/control sequences at the byte level."""
    out = bytearray()
    i = 0
    n = len(data)
    while i < n:
        b = data[i]
        if b != ESC:
            out.append(b)
            i += 1
            continue

        if i + 1 >= n:
            break
        nxt = data[i + 1]

        # CSI: ESC [
        if nxt == ord("["):
            i += 2
            while i < n:
                b = data[i]
                if 0x40 <= b <= 0x7E:
                    i += 1
                    break
                i += 1
            continue

        # OSC: ESC ]
        if nxt == ord("]"):
            i += 2
            while i < n:
                b = data[i]
                if b == BEL:
                    i += 1
                    break
                if b == ESC and i + 1 < n and data[i + 1] == ord("\\"):
                    i += 2
                    break
                i += 1
            continue

        # DCS/APC/PM/SOS: ESC P/ _/ ^/ X ... ESC \
        if nxt in (ord("P"), ord("_"), ord("^"), ord("X")):
            i += 2
            while i < n:
                b = data[i]
                if b == ESC and i + 1 < n and data[i + 1] == ord("\\"):
                    i += 2
                    break
                i += 1
            continue

        # Single-character escapes; skip ESC and following byte.
        i += 2

    return out.decode("utf-8", errors="replace")


def _normalize_controls(text: str) -> str:
    """Normalize CR/LF and drop remaining control chars."""
    lines = []
    line: list[str] = []
    ends_with_newline = text.endswith("\n")
    i = 0
    n = len(text)

    while i < n:
        ch = text[i]
        if ch == "\r":
            if i + 1 < n and text[i + 1] == "\n":
                lines.append("".join(line))
                line = []
                i += 2
                continue
            line = []
            i += 1
            continue
        if ch == "\n":
            lines.append("".join(line))
            line = []
            i += 1
            continue
        if ch == "\b":
            if line:
                line.pop()
            i += 1
            continue
        if ch == "\t":
            line.append(ch)
            i += 1
            continue
        if ord(ch) < 32 or ord(ch) == 127:
            i += 1
            continue
        line.append(ch)
        i += 1

    if line:
        lines.append("".join(line))

    result = "\n".join(lines)
    if ends_with_newline:
        result += "\n"
    return result


def _read_bytes(path: Optional[str]) -> bytes:
    if not path or path == "-":
        return sys.stdin.buffer.read()
    with open(path, "rb") as f:
        return f.read()


def _write_text(path: Optional[str], text: str) -> None:
    if not path or path == "-":
        sys.stdout.write(text)
        return
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main() -> int:
    parser = argparse.ArgumentParser(description="Strip ANSI/control codes from logs.")
    parser.add_argument("-i", "--input", help="Input file (default: stdin)")
    parser.add_argument("-o", "--output", help="Output file (default: stdout)")
    args = parser.parse_args()

    data = _read_bytes(args.input)
    text = _strip_ansi_bytes(data)
    cleaned = _normalize_controls(text)
    _write_text(args.output, cleaned)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
