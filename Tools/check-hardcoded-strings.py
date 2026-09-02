#!/usr/bin/env python3
"""Guard against hardcoded non-English UI strings (FER-472).

The app's String Catalog is `sourceLanguage: en`: every user-facing string must be an ENGLISH literal
(the key) so it can carry an `es` translation and switch with the app language. A Spanish literal in a
`Text(...)`/`Label(...)`/`String(localized:)`/etc. becomes a Spanish *key* that never translates to
English — exactly the debt this guard prevents from creeping back in.

Heuristic: flag a string literal that contains Spanish-only characters (¿¡ñ«», accented vowels) inside
a user-facing SwiftUI call. Data values (engine metric labels) and the «Patrones» brand are allow-listed.

Usage:  python3 Tools/check-hardcoded-strings.py [file.swift ...]
Default scope: localized app screens. Add more files as they're cleaned. Exits non-zero on a hit.
"""
import re, sys

DEFAULT_FILES = [
    # FER-240: Patrones screen archived — Bucle*.swift removed from the default scope.
    "Cenit/Screens/TodayView.swift",                                  # FER-744
    "Cenit/Screens/EntrenarView.swift",                               # FER-816 (Formas/formOptions → catalog)
    "Cenit/Screens/Hoy/*.swift",                                      # FER-audit: la lógica de Hoy vive aquí
    "Cenit/Data/ReceiptMapping.swift",                                # FER-112 (el recibo térmico)
    "Cenit/Data/TicketMapping.swift",                                 # FER-112
    "Cenit/Screens/ReceiptPrinterScreen.swift",                       # FER-112
]

# El PAQUETE de diseño, entero y sin excepciones (FER-112).
#
# Aquí la deuda no es que una cadena en español sea difícil de traducir: es que **no se puede**.
# `CenitDesign` no tiene catálogo, así que cualquier texto que nazca dentro se queda para
# siempre en el idioma en que se escribió. Así vivió el dock —la barra de TODAS las pantallas—
# diciendo «Hoy · Tendencias · Entrenar · Ajustes» con el teléfono en inglés, con un TODO
# abierto desde julio que nadie iba a ver.
#
# Por eso este barrido va sobre el paquete COMPLETO y no sobre una lista opt-in: los archivos
# que aún no existen son justo los que hay que vigilar. Un componente que necesita texto lo
# recibe del app (`LiquidTabRotulos`, `EcosistemaRotulos`, `ThermalReceipt`), nunca lo escribe.
PAQUETES_SIN_CATALOGO = [
    "Packages/CenitDesign/Sources/**/*.swift",
    "Packages/StrandTraining/Sources/**/*.swift",
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

# Bloques que NO llegan al usuario: `#if DEBUG` y los `#Preview` sueltos (no todos viven
# dentro de un DEBUG). Se recortan conservando los saltos de línea para no mover los números.
PREVIEW = re.compile(r"#if DEBUG.*?#endif|#Preview\([^)]*\)\s*\{.*?\n\}", re.S)

def main(files):
    hits = []
    for path in files:
        try:
            src = open(path, encoding="utf-8").read()
        except FileNotFoundError:
            print(f"skip (not found): {path}"); continue
        # Lo que vive tras `#if DEBUG` (previews, demos, arneses) no llega al usuario: se ignora,
        # pero conservando los saltos de línea para que los números de línea sigan siendo ciertos.
        src = PREVIEW.sub(lambda m: "\n" * m.group(0).count("\n"), src)
        lines = src.splitlines()
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
    import glob
    patterns = sys.argv[1:] or (DEFAULT_FILES + PAQUETES_SIN_CATALOGO)
    files = [f for pat in patterns for f in (sorted(glob.glob(pat, recursive=True)) or [pat])]
    sys.exit(main(files))
