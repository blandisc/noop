#!/usr/bin/env python3
"""FER-1027 — guarda de copy: ninguna cadena user-facing debe mencionar la banda.

Post FER-1003 (Cénit sin banda), el copy que le habla al «strap»/«your band» le
miente a un usuario nuevo (que nunca tiene datos de banda). Este guard atrapa
regresiones: cadenas mostradas al usuario en Cenit/Screens que nombren la banda.

Alcance: solo el sentido DISPOSITIVO — `strap`, `your band`, `tu banda`. NO
`the band` (falso positivo: «the band is your normal range», rango estadístico).
Excluye comentarios, identificadores de código, y CyclePhaseView (función de
banda oculta a propósito; sus cadenas quedan dormidas). Corre en CI-lite y a mano.
"""
import re
import sys
from pathlib import Path

SCREENS = Path("Cenit/Screens")
# Solo estas formas cuentan como copy user-facing.
UI_CTX = re.compile(r'(Text\(|String\(localized:|message:|note:|body:|title:|headline:|prose:|subtitle:|anchorMedia:|return\s+")')
# Sentido dispositivo, sin falsos positivos de «the band» (rango).
DEVICE = re.compile(r'\bstrap\b|your band\b|tu banda\b', re.IGNORECASE)
# Identificadores de código que contienen «strap» pero no son copy.
CODE_IDENT = re.compile(r'strapHrv|deviceId|strap-noop|strapOnly|strapSleeps|strapSession|strapDays|storedStrap|latestStrapNight|source:\s*"strap"|series\("strap"|\.strap\b|noStrapFallback')
# «band» en sentido RANGO estadístico (rango normal, banda de incertidumbre de Body Age,
# banda de volumen 10–20 series) — NO es la banda WHOOP. Falsos positivos legítimos.
RANGE_BAND = re.compile(r'Your band"|the band is your|bandYears|within the band|above the band|below the band|sets-per-week band|typical swing')

def main() -> int:
    offenders = []
    for f in sorted(SCREENS.glob("*.swift")):
        if f.name == "CyclePhaseView.swift":
            continue  # función de banda oculta (AjustesView la gatea en !usesWhoop)
        for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            s = line.strip()
            if s.startswith("//"):
                continue
            if not DEVICE.search(line):
                continue
            if not UI_CTX.search(line):
                continue
            if CODE_IDENT.search(line):
                continue
            if RANGE_BAND.search(line):
                continue  # «band» = rango estadístico, no la banda WHOOP
            offenders.append(f"{f}:{i}: {s[:120]}")
    if offenders:
        print("❌ Copy de banda alcanzable por un usuario Apple-only (neutralízalo):")
        print("\n".join(offenders))
        return 1
    print("✅ Ninguna cadena user-facing menciona la banda (strap/your band).")
    return 0

if __name__ == "__main__":
    sys.exit(main())
