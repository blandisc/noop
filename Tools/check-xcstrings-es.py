#!/usr/bin/env python3
"""Falla si aparece una clave NUEVA sin traducción `es` en `Localizable.xcstrings`.

La auditoría de Hoy (FER-audit) encontró strings en inglés que veía un usuario es-MX
(«Getting to know you», «Unloading»…): no había ningún gate para «falta es». Este lo cierra
sin exigir traducir las 129 heredadas de golpe — usa una línea base (`Tools/i18n-es-baseline.txt`)
y solo falla sobre las que se agreguen de ahora en adelante. Para bajar la base: traduce y
quita su clave del archivo.
"""
import json, sys, os

CAT = "Cenit/Resources/Localizable.xcstrings"
BASELINE = os.path.join(os.path.dirname(__file__), "i18n-es-baseline.txt")

def missing_es():
    strings = json.load(open(CAT, encoding="utf-8")).get("strings", {})
    out = set()
    for key, entry in strings.items():
        # una clave vacía "" no necesita traducción; el resto sí.
        if key.strip() == "": continue   # claves de formato/espaciado no son copy
        es = entry.get("localizations", {}).get("es", {}).get("stringUnit", {}).get("value")
        if not es:
            out.add(key)
    return out

def main():
    missing = missing_es()
    base = set(l.rstrip("\n") for l in open(BASELINE, encoding="utf-8")) if os.path.exists(BASELINE) else set()
    nuevas = sorted(missing - base)
    if nuevas:
        print(f"{len(nuevas)} clave(s) NUEVA(s) sin traducción es-MX (agrégalas al catálogo):")
        print("\n".join(f"  {k!r}" for k in nuevas[:40]))
        return 1
    # Aviso amable si la base bajó (para poder recortarla).
    resueltas = base - missing
    if resueltas:
        print(f"ℹ️  {len(resueltas)} de la base ya tienen es — quítalas de i18n-es-baseline.txt.")
    print(f"✅ sin claves nuevas sin es ({len(missing)} heredadas en la base)")
    return 0

sys.exit(main())
