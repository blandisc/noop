#!/usr/bin/env python3
"""Guard against hardcoded non-English UI strings (FER-472).

The app's String Catalog is `sourceLanguage: en`: every user-facing string must be an ENGLISH literal
(the key) so it can carry an `es` translation and switch with the app language. A Spanish literal in a
`Text(...)`/`Label(...)`/`String(localized:)`/etc. becomes a Spanish *key* that never translates to
English — exactly the debt this guard prevents from creeping back in.

Heuristic: flag a string literal that contains Spanish-only characters (¿¡ñ«», accented vowels) inside
a user-facing SwiftUI call. Data values (engine metric labels) and the «Patrones» brand are allow-listed.

Usage:  python3 Tools/check-hardcoded-strings.py [file.swift ...]
Default scope: the localized Patrones screen. Add more files as they're cleaned. Exits non-zero on a hit.
"""
import re, sys

DEFAULT_FILES = [
    "Cenit/Screens/BucleView.swift",
    "Cenit/Screens/BucleSheets.swift",
    "Cenit/Screens/TodayView.swift",                                  # FER-744
    "Packages/StrandDesign/Sources/StrandDesign/FiveRules.swift",     # FER-744
    "Cenit/Screens/EntrenarView.swift",                               # FER-816 (Formas/formOptions → catalog)
]

# Engine/data values that are intentionally the metric's stored label, and the brand name.
ALLOW = {"Recuperación", "Patrones"}
# Brand tokens that carry accented characters yet are the same in English copy — stripped
# before the Spanish-only check so an English string like "Support Cénit" isn't flagged.
BRAND = ["Cénit"]

CALL = r'(?:Text|Label|Button|String\(localized:|accessibilityLabel|accessibilityHint|navigationTitle|' \
       r'sectionLabel|stepRow|comingRow|evidenceRow|breakdownBar|answerPill|checkInToggle|confirmationDialog|alert)'
# A user-facing call whose first string literal contains a Spanish-only character.
PAT = re.compile(CALL + r'\(\s*(?:[^)]*?,\s*)?"([^"]*[¿¡ñÑ«»áéíóúÁÉÍÓÚ][^"]*)"')

def main(files):
    hits = []
    for path in files:
        try:
            lines = open(path, encoding="utf-8").read().splitlines()
        except FileNotFoundError:
            print(f"skip (not found): {path}"); continue
        for i, line in enumerate(lines, 1):
            s = line.strip()
            if s.startswith("//") or s.startswith("///"):
                continue
            for m in PAT.finditer(line):
                lit = m.group(1)
                if lit in ALLOW:
                    continue
                # Strip brand tokens; if no Spanish-only char remains, it's English copy.
                stripped = lit
                for b in BRAND:
                    stripped = stripped.replace(b, "")
                if not re.search(r"[¿¡ñÑ«»áéíóúÁÉÍÓÚ]", stripped):
                    continue
                hits.append((path, i, lit))
    if hits:
        print("❌ Hardcoded non-English UI string(s) found — use an English key + es translation in the catalog:")
        for path, i, lit in hits:
            print(f"   {path}:{i}: \"{lit}\"")
        return 1
    print(f"✅ no hardcoded non-English UI strings in {len(files)} file(s)")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or DEFAULT_FILES))
