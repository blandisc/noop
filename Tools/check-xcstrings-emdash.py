#!/usr/bin/env python3
"""Falla si un valor **es** de `Localizable.xcstrings` trae un guion largo (—, U+2014).

El punto ciego que cazó la auditoría de Hoy (FER-audit): `check-design-drift.py
--rules no-emdash-string` solo abre `.swift` (el inglés), nunca el catálogo — así que el
copy en ESPAÑOL, que es el que ve el usuario es-MX, se colaba. Regla (FER-879): «:», «·» o
coma, nunca «—». (El inglés ya lo audita design-lint sobre las pantallas.)
"""
import json, sys, glob

def main():
    bad = []
    for path in sorted(glob.glob("**/Localizable.xcstrings", recursive=True)):
        if ".build" in path: continue
        strings = json.load(open(path, encoding="utf-8")).get("strings", {})
        for key, entry in strings.items():
            es = entry.get("localizations", {}).get("es", {}).get("stringUnit", {}).get("value", "")
            if "—" in es:
                bad.append(f"{path}: {key!r}: {es!r}")
    if bad:
        print("Guion largo (—) en copy ESPAÑOL — usa «:», «·» o coma (FER-879):")
        print("\n".join(f"  {b}" for b in bad))
        return 1
    print("✅ sin em-dash en valores es de Localizable.xcstrings")
    return 0

sys.exit(main())
