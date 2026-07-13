#!/usr/bin/env python3
"""Guard against design-system drift in the screens (auditoría jul-2026).

`Packages/StrandDesign` is the single source of visual truth. A screen must not re-introduce a raw
hex, an ad-hoc `.font(.system(size:))`, a literal corner radius, or a magic opacity — each is a token
in the package (see `CenitMetrics`, `StrandFont.glyph`/`.micro`, `InstrumentoCardRadius`, `StrandOpacity`).
This linter fails with concrete `file:line: rule — snippet` lines when it finds one.

Rules (each activated in the PR that finishes its migration — pass `--rules` to opt in incrementally):

    no-hex             `Color(hex:` outside Packages/StrandDesign            (already clean — on by default)
    no-adhoc-font      `.font(.system(size:`                                 (after task 02)
    no-radius-literal  `cornerRadius: <number>` not using a CenitMetrics token (after task 01)
    no-opacity-literal `.opacity(<number>)` not using StrandOpacity/helpers   (after task 03)
    no-emdash-string   em-dash (—) inside a Swift string literal (copy rule)   (FER-878/879; on for Screens+Onboarding)

Per-line escape: a trailing `// token-exempt: <reason>` silences every rule on that line (geometry of
data — bars, legends, swatches, keypad, Dynamic-Island widget — that legitimately needs a literal).

Usage:
    python3 Tools/check-design-drift.py                       # scan default roots, all rules
    python3 Tools/check-design-drift.py --rules no-hex        # only these rules
    python3 Tools/check-design-drift.py Cenit/Screens/X.swift # scan given files (pre-commit passes staged paths)

Exits non-zero on any hit.
"""
import re, sys, os

DEFAULT_ROOTS = ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/AI", "Cenit/App", "CenitWidgets", "CenitWatch"]
DESIGN_PKG = "Packages/StrandDesign"
EXEMPT = re.compile(r"//\s*token-exempt\b")

ALL_RULES = ["no-hex", "no-adhoc-font", "no-radius-literal", "no-opacity-literal", "no-emdash-string"]

# no-emdash-string: an em-dash (—, U+2014) inside a user-facing Swift string literal. ADN copy rule
# (FER-878): on-screen copy uses «:», «·» or a comma, never an em-dash. Scoped to STRING LITERALS so the
# thousands of legitimate em-dashes in comments/doc-comments are ignored, and the bare «—» no-data
# placeholder glyph (a string with no letters) is allowed — only em-dashes used as a copy connector
# (a quoted span that also contains a letter) are flagged.
RE_STRING_SPAN = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')
RE_HAS_LETTER = re.compile(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]")


def _emdash_string_hit(line):
    for m in RE_STRING_SPAN.finditer(line):
        content = m.group(1)
        if "—" in content and RE_HAS_LETTER.search(content):
            return True
    return False

# no-hex: any Color(hex: … outside the design package.
RE_HEX = re.compile(r"Color\(hex:")
# no-adhoc-font: a font built from a *literal* point size. Like no-radius-literal / no-opacity-literal,
# it only flags a bare digit — `.font(.system(size: WidgetMetrics.hero))` / `.system(size: M.name)` source
# the size from a design token and pass; `.font(.system(size: 13))` is the magic number it's meant to catch.
RE_FONT = re.compile(r"\.font\(\.system\(size:\s*[0-9]")
# no-radius-literal: cornerRadius: followed by a bare number (a token ref like CenitMetrics.cardRadius,
# radius.value, or M.foo is a name, not a digit, so it's allowed).
RE_RADIUS = re.compile(r"cornerRadius:\s*[0-9]")
# no-opacity-literal: .opacity( followed by a bare number. `.opacity(StrandOpacity.x)`,
# `.opacity(theme.tint(...))`, `.opacity(someVar)` all start with a non-digit and pass.
RE_OPACITY = re.compile(r"\.opacity\(\s*[0-9.]")

RULE_PATTERNS = {
    "no-hex": RE_HEX,
    "no-adhoc-font": RE_FONT,
    "no-radius-literal": RE_RADIUS,
    "no-opacity-literal": RE_OPACITY,
}


def iter_swift_files(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p):
                for f in files:
                    if f.endswith(".swift"):
                        yield os.path.join(root, f)
        elif p.endswith(".swift"):
            yield p


def check(paths, rules):
    hits = []
    for path in iter_swift_files(paths):
        # no-hex only applies OUTSIDE the design package (the package is where hex is allowed).
        in_design_pkg = DESIGN_PKG in path.replace("\\", "/")
        try:
            lines = open(path, encoding="utf-8").read().splitlines()
        except FileNotFoundError:
            continue
        for i, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
                continue
            if EXEMPT.search(line):
                continue
            for rule in rules:
                if rule == "no-hex" and in_design_pkg:
                    continue
                if rule == "no-emdash-string":
                    if _emdash_string_hit(line):
                        hits.append((path, i, rule, stripped[:100]))
                    continue
                m = RULE_PATTERNS[rule].search(line)
                if m:
                    hits.append((path, i, rule, stripped[:100]))
    return hits


def main(argv):
    rules = ALL_RULES
    files = []
    it = iter(argv)
    for arg in it:
        if arg == "--rules":
            rules = next(it).split(",")
        elif arg.startswith("--rules="):
            rules = arg.split("=", 1)[1].split(",")
        else:
            files.append(arg)
    unknown = [r for r in rules if r not in ALL_RULES]
    if unknown:
        print(f"unknown rule(s): {', '.join(unknown)} (known: {', '.join(ALL_RULES)})")
        return 2
    roots = files or DEFAULT_ROOTS
    hits = check(roots, rules)
    if hits:
        print("❌ design-system drift — promote the value to a StrandDesign token, "
              "or annotate the line with `// token-exempt: <reason>`:")
        for path, i, rule, snippet in hits:
            print(f"   {path}:{i}: {rule} — {snippet}")
        return 1
    print(f"✅ no design drift ({', '.join(rules)}) in {', '.join(roots)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
