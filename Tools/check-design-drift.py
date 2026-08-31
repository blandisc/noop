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
    no-spacing-literal `.padding(<n>)`, `spacing: <n>`, `lineWidth: <n>`       (FER-258; ratchet over Cenit/Screens)

Per-line escape: a trailing `// token-exempt: <reason>` silences every rule on that line (geometry of
data — bars, legends, swatches, keypad, Dynamic-Island widget — that legitimately needs a literal).

Ratchet: `--baseline <json>` grandfathers the hits a rule already has, per file. A file may keep the
count the baseline records for it; one hit MORE fails. That is how a rule turns on green over a tree
that is only partly migrated (FER-258): the debt stops growing while the sweeps continue. When a file
drops below its allowance the run stays green and prints a note to re-record the baseline (tighten it),
so the number can only go down. `--write-baseline <json>` records the current tree.

Usage:
    python3 Tools/check-design-drift.py                       # scan default roots, all rules
    python3 Tools/check-design-drift.py --rules no-hex        # only these rules
    python3 Tools/check-design-drift.py Cenit/Screens/X.swift # scan given files (pre-commit passes staged paths)

Exits non-zero on any hit.
"""
import re, sys, os, json

DEFAULT_ROOTS = ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/AI", "Cenit/App", "CenitWidgets", "CenitWatch"]
DESIGN_PKG = "Packages/StrandDesign"
EXEMPT = re.compile(r"//\s*token-exempt\b")

ALL_RULES = ["no-hex", "no-adhoc-font", "no-radius-literal", "no-opacity-literal", "no-emdash-string", "no-raw-shadow", "no-sheet-glass", "no-spacing-literal"]

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
# no-raw-shadow: an inline `.shadow(` in a screen. Elevation is a token now (`.strandElevation(_:ink:)`);
# a hand-rolled drop shadow in a screen should either use it or be a documented exception. Deliberate
# non-standard shadows (the thermal receipt, upward-casting sheets, ambient glows) carry `// token-exempt:`.
RE_SHADOW = re.compile(r"\.shadow\(")
# no-sheet-glass: `.liquidGlass(.superficie)` / `.pastilla` en una superficie INTERNA de hoja.
# Es el defecto de las «tablas grises» (FER-29/FER-33): esas recetas muestrean el fondo, y dentro
# de una hoja —que ya es vidrio— el resultado salta de gris a blanco al arrastrarla. Las tarjetas
# internas van en PAPEL OPACO (`.superficieSolida` / `.pastillaSolida`); el vidrio de verdad se
# reserva para la hoja misma (`LiquidSheetFondo`), el dock y el orbe. Nada lo detectaba, y por eso
# se coló tres veces. Una superficie que de verdad quiera vidrio lleva `// token-exempt:` con la razón.
RE_SHEET_GLASS = re.compile(r"\.liquidGlass\(\.(superficie|pastilla)\)")
# no-spacing-literal: the class of defect that ate four deliveries in three days (FER-205/207/208/164)
# and kept coming back because nothing watched the spacing numbers. Flags a bare digit in the three
# places a screen writes distance by hand: `.padding(14)` / `.padding(.top, 14)`, `spacing: 14` (stacks
# and grids) and `lineWidth: 2` (strokes). A token reference — `CenitMetrics.space2`, `LiquidSpace.s400`,
# `M.gap` — is a name, not a digit, so it passes. Real data geometry carries `// token-exempt:`.
RE_SPACING = re.compile(
    r"\.padding\(\s*[0-9]"                    # .padding(14)
    r"|\.padding\(\s*\.[a-zA-Z]+\s*,\s*[0-9]"  # .padding(.top, 14)
    r"|\bspacing:\s*[0-9]"                     # VStack(spacing: 14)
    r"|\blineWidth:\s*[0-9]"                   # .stroke(_, lineWidth: 2)
)

RULE_PATTERNS = {
    "no-hex": RE_HEX,
    "no-adhoc-font": RE_FONT,
    "no-radius-literal": RE_RADIUS,
    "no-opacity-literal": RE_OPACITY,
    "no-raw-shadow": RE_SHADOW,
    "no-sheet-glass": RE_SHEET_GLASS,
    "no-spacing-literal": RE_SPACING,
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


def _key(path):
    return path.replace("\\", "/").lstrip("./")


def tally(hits):
    """{rule: {file: count}} — the shape the baseline records."""
    out = {}
    for path, _i, rule, _snippet in hits:
        out.setdefault(rule, {})[_key(path)] = out.setdefault(rule, {}).get(_key(path), 0) + 1
    return out


def apply_baseline(hits, baseline):
    """Split hits into (over-budget, stale-note). A file keeps the count the baseline allows it;
    the hits above that allowance are what fails."""
    allowed = {r: dict(f) for r, f in baseline.items()}
    over = []
    for hit in hits:
        path, _i, rule, _snippet = hit
        budget = allowed.get(rule, {}).get(_key(path), 0)
        if budget > 0:
            allowed[rule][_key(path)] = budget - 1
        else:
            over.append(hit)
    stale = [(rule, f, left) for rule, files in allowed.items() for f, left in files.items() if left > 0]
    return over, stale


def main(argv):
    rules = ALL_RULES
    files = []
    baseline_path = None
    write_baseline = None
    it = iter(argv)
    for arg in it:
        if arg == "--rules":
            rules = next(it).split(",")
        elif arg.startswith("--rules="):
            rules = arg.split("=", 1)[1].split(",")
        elif arg == "--baseline":
            baseline_path = next(it)
        elif arg.startswith("--baseline="):
            baseline_path = arg.split("=", 1)[1]
        elif arg == "--write-baseline":
            write_baseline = next(it)
        elif arg.startswith("--write-baseline="):
            write_baseline = arg.split("=", 1)[1]
        else:
            files.append(arg)
    unknown = [r for r in rules if r not in ALL_RULES]
    if unknown:
        print(f"unknown rule(s): {', '.join(unknown)} (known: {', '.join(ALL_RULES)})")
        return 2
    roots = files or DEFAULT_ROOTS
    hits = check(roots, rules)
    if write_baseline:
        with open(write_baseline, "w", encoding="utf-8") as fh:
            json.dump(tally(hits), fh, indent=2, sort_keys=True, ensure_ascii=False)
            fh.write("\n")
        print(f"📝 baseline recorded in {write_baseline} ({len(hits)} grandfathered hits)")
        return 0
    stale = []
    if baseline_path:
        try:
            baseline = json.load(open(baseline_path, encoding="utf-8"))
        except FileNotFoundError:
            print(f"baseline not found: {baseline_path}")
            return 2
        hits, stale = apply_baseline(hits, {r: v for r, v in baseline.items() if r in rules})
    if hits:
        print("❌ design-system drift — promote the value to a StrandDesign token, "
              "or annotate the line with `// token-exempt: <reason>`:")
        for path, i, rule, snippet in hits:
            print(f"   {path}:{i}: {rule} — {snippet}")
        if baseline_path:
            print(f"   (these are ABOVE the debt {baseline_path} grandfathers — the baseline never grows)")
        return 1
    print(f"✅ no design drift ({', '.join(rules)}) in {', '.join(roots)}")
    for rule, f, left in sorted(stale):
        print(f"   ↓ {f}: {left} fewer {rule} — re-record with --write-baseline {baseline_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
