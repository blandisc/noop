#!/usr/bin/env python3
"""Find (and optionally delete) keys in a String Catalog that no source file references.

Why this exists (FER-994 E1)
---------------------------
`Cenit/Resources/Localizable.xcstrings` is compiled whole into the binary, so every
orphan key from a retired screen (or from the old Mac/Android era) ships to users.
Xcode's own `"extractionState": "stale"` marker is NOT a safe deletion criterion: the
IDE's extractor only sees `Text("literal")`-shaped call sites, so it marks live keys
stale — and then eats their `es` values. This script decides with the real criterion:

    a key is dead <=> its text appears nowhere in the source tree.

It is deliberately biased toward keeping keys. A key survives if ANY of these hold:

  1. it is an exact string literal in a `.swift` file;
  2. its interpolation-normalized form matches a literal (SwiftUI turns
     `Text("Night · \\(n) cycles")` into the key `Night · %lld cycles`, so format
     specifiers are compared against `\\(...)` slots);
  3. its raw text occurs anywhere in the source corpus (comments included);
  4. it is a format string and every one of its literal segments occurs in the corpus
     (covers keys assembled across lines or via `String(localized:)` helpers);
  5. it appears in a non-Swift resource we also scan (plists, JSON, yml, stringsdict).

Cost asymmetry: a surviving dead key costs ~30 bytes; a deleted live key shows English
to an es-MX user. When in doubt this script keeps the key.

Usage
-----
    python3 Tools/find-dead-strings.py                    # report
    python3 Tools/find-dead-strings.py --list             # report + every dead key
    python3 Tools/find-dead-strings.py --json out.json    # machine-readable
    python3 Tools/find-dead-strings.py --apply            # delete dead keys in place

`--apply` rewrites the catalog by deleting whole key blocks textually (never a JSON
round-trip), so the diff is exactly the removed keys and nothing else.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = REPO / "Cenit/Resources/Localizable.xcstrings"

# Every place Swift (or a resource) could name a key. CenitWatch has its own catalog,
# but its sources are scanned too: a shared string must never be considered dead here.
SOURCE_DIRS = [
    "Cenit",
    "CenitApp",
    "CenitShared",
    "CenitWatch",
    "CenitWidgets",
    "CenitUnitTests",
    "CenitUITests",
    "Packages",
    "Tools",
]

SKIP_DIR_PARTS = {".build", "DerivedData", ".git", "build", "Pods", ".swiftpm"}

# Non-Swift files that can legitimately carry a user-facing string.
EXTRA_SUFFIXES = {".plist", ".stringsdict", ".json", ".yml", ".yaml", ".strings", ".md"}

# printf-style specifier, including positional (%1$@) and width/precision forms.
FORMAT_SPEC = re.compile(
    r"%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@dioupxXeEfFgGaAcsSn]"
)
PLACEHOLDER = "\x00"


def normalize_format(text: str) -> str:
    """Collapse every printf specifier to a single sentinel (`%%` stays a percent)."""
    out: list[str] = []
    i = 0
    while i < len(text):
        if text[i] == "%":
            if text.startswith("%%", i):
                out.append("%")
                i += 2
                continue
            m = FORMAT_SPEC.match(text, i)
            if m:
                out.append(PLACEHOLDER)
                i = m.end()
                continue
        out.append(text[i])
        i += 1
    return "".join(out)


def iter_source_files(root: Path):
    for d in SOURCE_DIRS:
        base = root / d
        if not base.is_dir():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            if SKIP_DIR_PARTS & set(path.parts):
                continue
            if path.suffix == ".swift" or path.suffix in EXTRA_SUFFIXES:
                yield path


SWIFT_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}


def extract_literals(src: str) -> tuple[set[str], set[str]]:
    """Return (exact literals, interpolation-normalized literals) found in Swift source.

    Handles single-line, multiline and raw string literals. Interpolation segments
    (`\\(...)`) become the sentinel so they can be matched against format specifiers.
    Comments are not stripped — a literal in a comment counts as a reference, which is
    the safe direction.
    """
    exact: set[str] = set()
    normalized: set[str] = set()
    i, n = 0, len(src)
    while i < n:
        # Raw string: (#+)" ... "(#+)
        if src[i] == "#":
            j = i
            while j < n and src[j] == "#":
                j += 1
            hashes = src[i:j]
            if j < n and src[j] == '"':
                is_multi = src.startswith('"""', j)
                delim = ('"""' if is_multi else '"') + hashes
                start = j + (3 if is_multi else 1)
                end = src.find(delim, start)
                if end == -1:
                    i = j + 1
                    continue
                body = src[start:end]
                exact.add(body)
                normalized.add(body)
                i = end + len(delim)
                continue
            i = j
            continue

        if src[i] == '"':
            is_multi = src.startswith('"""', i)
            start = i + (3 if is_multi else 1)
            closing = '"""' if is_multi else '"'
            buf: list[str] = []
            norm: list[str] = []
            j = start
            ok = False
            while j < n:
                c = src[j]
                if c == "\\" and j + 1 < n:
                    nxt = src[j + 1]
                    if nxt == "(":  # interpolation — skip balanced parens
                        depth = 1
                        k = j + 2
                        while k < n and depth:
                            if src[k] == "(":
                                depth += 1
                            elif src[k] == ")":
                                depth -= 1
                            k += 1
                        buf.append(PLACEHOLDER)
                        norm.append(PLACEHOLDER)
                        j = k
                        continue
                    if nxt == "u" and src.startswith("\\u{", j):
                        close = src.find("}", j)
                        if close != -1:
                            try:
                                ch = chr(int(src[j + 3 : close], 16))
                            except ValueError:
                                ch = ""
                            buf.append(ch)
                            norm.append(ch)
                            j = close + 1
                            continue
                    ch = SWIFT_ESCAPES.get(nxt, nxt)
                    buf.append(ch)
                    norm.append(ch)
                    j += 2
                    continue
                if not is_multi and c == "\n":
                    break  # unterminated single-line literal
                if src.startswith(closing, j):
                    ok = True
                    break
                buf.append(c)
                norm.append(c)
                j += 1
            if ok:
                body = "".join(buf)
                # Multiline literals carry the closing delimiter's indentation; strip it.
                exact.add(body.replace(PLACEHOLDER, ""))
                exact.add(body)
                normalized.add("".join(norm))
                i = j + len(closing)
                continue
            i += 1
            continue
        i += 1
    return exact, normalized


def build_corpus(root: Path):
    exact: set[str] = set()
    normalized: set[str] = set()
    raw_parts: list[str] = []
    files = 0
    for path in iter_source_files(root):
        try:
            src = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        files += 1
        raw_parts.append(src)
        if path.suffix == ".swift":
            e, nm = extract_literals(src)
            exact |= e
            normalized |= nm
    return exact, normalized, "\n".join(raw_parts), files


def literal_segments(key: str) -> list[str]:
    """Non-empty literal chunks of a format string, split on the specifiers."""
    return [s for s in normalize_format(key).split(PLACEHOLDER) if s.strip()]


def is_alive(key: str, exact: set[str], normalized: set[str], raw: str) -> str | None:
    """Return the reason the key is considered referenced, or None if it looks dead."""
    if not key.strip():
        return "empty/whitespace key (left alone)"
    if key in exact:
        return "exact literal"
    norm = normalize_format(key)
    if norm in normalized or norm in exact:
        return "interpolated literal"
    if key in raw:
        return "raw substring in source"
    segments = literal_segments(key)
    if segments and norm != key:
        # Format string: keep it if every literal chunk shows up somewhere. Very short
        # chunks ("·", " of ") match everything, so they don't count as evidence — but a
        # key made only of such chunks is kept anyway rather than risk a false positive.
        meaningful = [s for s in segments if len(s.strip()) >= 4]
        if not meaningful:
            return "format string with only trivial segments (kept out of caution)"
        if all(s in raw for s in meaningful):
            return "all format segments in source"
    return None


# ---------------------------------------------------------------------------
# Textual block surgery — deletion only, no reformat.
# ---------------------------------------------------------------------------

KEY_LINE = re.compile(r'^    ("(?:[^"\\]|\\.)*") : \{')


def parse_blocks(lines: list[str]) -> tuple[int, list[tuple[str, int, int]], int]:
    """Locate each top-level key block. Returns (header_end, blocks, footer_start).

    blocks: [(key, first_line_idx, last_line_idx_inclusive)] in file order.
    """
    blocks: list[tuple[str, int, int]] = []
    header_end = None
    i = 0
    while i < len(lines):
        m = KEY_LINE.match(lines[i])
        if m:
            if header_end is None:
                header_end = i
            key = json.loads(m.group(1))
            depth = lines[i].count("{") - lines[i].count("}")
            j = i
            while depth > 0:
                j += 1
                depth += lines[j].count("{") - lines[j].count("}")
            blocks.append((key, i, j))
            i = j + 1
            continue
        i += 1
    if header_end is None:
        raise SystemExit("no key blocks found — is this a String Catalog?")
    footer_start = blocks[-1][2] + 1
    return header_end, blocks, footer_start


def apply_deletions(catalog: Path, dead: set[str]) -> int:
    text = catalog.read_text(encoding="utf-8")
    lines = text.split("\n")
    header_end, blocks, footer_start = parse_blocks(lines)
    kept = [b for b in blocks if b[0] not in dead]
    if len(kept) == len(blocks):
        return 0
    out = lines[:header_end]
    for idx, (_key, start, end) in enumerate(kept):
        block = lines[start : end + 1]
        block[-1] = block[-1].rstrip(",")  # normalize; comma re-added below
        if idx != len(kept) - 1:
            block[-1] += ","
        out.extend(block)
    out.extend(lines[footer_start:])
    catalog.write_text("\n".join(out), encoding="utf-8")
    return len(blocks) - len(kept)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    ap.add_argument("--root", type=Path, default=REPO)
    ap.add_argument("--list", action="store_true", help="print every dead key")
    ap.add_argument("--json", type=Path, help="write the dead-key list as JSON")
    ap.add_argument("--apply", action="store_true", help="delete the dead keys in place")
    args = ap.parse_args()

    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    keys = list(catalog["strings"].keys())

    exact, normalized, raw, n_files = build_corpus(args.root)
    print(f"scanned {n_files} source files; {len(exact)} literals, {len(normalized)} normalized")

    dead: list[str] = []
    for key in keys:
        if is_alive(key, exact, normalized, raw) is None:
            dead.append(key)

    print(f"catalog keys: {len(keys)}")
    print(f"dead (no reference anywhere): {len(dead)}")
    print(f"surviving: {len(keys) - len(dead)}")

    if args.list:
        for k in dead:
            print("DEAD\t" + k.replace("\n", "\\n"))
    if args.json:
        args.json.write_text(json.dumps(dead, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"wrote {args.json}")
    if args.apply:
        removed = apply_deletions(args.catalog, set(dead))
        print(f"removed {removed} key blocks from {args.catalog}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
