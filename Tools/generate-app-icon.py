#!/usr/bin/env python3
"""Genera el ícono de Cénit: el orbe de partículas (FER-41).

El ícono NO es un dibujo aparte del orbe que la app enseña — es el MISMO objeto, con las
mismas 300 direcciones de la espiral de Fibonacci, la misma proyección con profundidad y el
mismo reflejo especular que `EcosistemaSimulacion.particula` calcula en Swift. Por eso vive
como script y no como un PNG que alguien exportó una vez: si la esfera del héroe cambia, el
ícono se vuelve a generar en vez de quedarse contando otra historia.

La esfera va PLENA (sin el gauge de nivel). El nivel del héroe codifica un dato del usuario,
y un ícono no puede afirmar un dato: es la identidad del objeto, no una lectura.

Uso:  python3 Tools/generate-app-icon.py
Salida: CenitApp/Resources/Assets.xcassets/AppIcon.appiconset/icon-{light,dark,tinted}-1024.png
"""
from __future__ import annotations

import math
import pathlib

from PIL import Image, ImageDraw

LADO = 1024
SUPER = 3          # supermuestreo: se dibuja a 3× y se reduce, que es el antialias barato
N = 300            # EcosistemaSimulacion.Geometria.nEsfera
APLASTAMIENTO = 0.96
RADIO_REL = 0.40   # radio del orbe como fracción del lado (diámetro 0.80 — la retícula de Apple)

RAIZ = pathlib.Path(__file__).resolve().parent.parent
DESTINO = RAIZ / "CenitApp/Resources/Assets.xcassets/AppIcon.appiconset"
# El Watch tiene su propio appiconset y su propio nombre de archivo; si no se genera aquí, se
# queda con el ícono del ADN retirado y las dos plataformas del mismo producto dejan de
# parecerse (lo cazó la revisión adversarial de FER-41).
DESTINO_WATCH = RAIZ / "CenitWatch/Resources/Assets.xcassets/AppIcon.appiconset"


def direcciones(n: int) -> list[tuple[float, float, float]]:
    """La espiral de Fibonacci — el espejo exacto de `EcosistemaSimulacion.direccion`."""
    ga = math.pi * (3 - math.sqrt(5))
    out = []
    for i in range(n):
        y = 1 - 2 * (i + 0.5) / n
        r = math.sqrt(max(0.0, 1 - y * y))
        th = ga * i
        out.append((r * math.cos(th), y, r * math.sin(th)))
    return out


def vertical(lado: int, arriba: tuple[int, int, int], abajo: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (lado, lado))
    d = ImageDraw.Draw(img)
    for y in range(lado):
        k = y / max(1, lado - 1)
        d.line([(0, y), (lado, y)],
               fill=tuple(round(a + (b - a) * k) for a, b in zip(arriba, abajo)))
    return img


def disco_suave(lado: int, cx: float, cy: float, radio: float,
                color: tuple[int, int, int], alfa_max: float, plano: float) -> Image.Image:
    """Un disco con caída radial, calculado POR PÍXEL.

    `plano` es la fracción del radio que se queda a alfa plena antes de empezar a caer; el
    resto se apaga con un smoothstep. Con `plano` alto sale un cuerpo sólido de canto suave
    (el núcleo del orbe); con `plano` en cero, un brillo que decae desde el centro (el
    especular).

    Se calcula píxel a píxel a propósito. La versión ingenua —apilar N círculos concéntricos
    semitransparentes— no da un gradiente sino una ACUMULACIÓN: las alfas se componen una
    sobre otra y el centro sale opaco por más bajo que se ponga cada anillo. Así fue como el
    primer ícono acabó con una mordida blanca en vez de un reflejo.
    """
    mascara = Image.new("L", (lado, lado), 0)
    px = mascara.load()
    x0, x1 = max(0, int(cx - radio)), min(lado, int(cx + radio) + 1)
    y0, y1 = max(0, int(cy - radio)), min(lado, int(cy + radio) + 1)
    banda = max(1e-6, 1 - plano)
    for y in range(y0, y1):
        dy2 = (y - cy) ** 2
        for x in range(x0, x1):
            dist = math.sqrt((x - cx) ** 2 + dy2)
            if dist >= radio:
                continue
            k = min(1.0, max(0.0, (1 - dist / radio) / banda))
            px[x, y] = round(255 * alfa_max * k * k * (3 - 2 * k))   # smoothstep
    capa = Image.new("RGBA", (lado, lado), (*color, 0))
    capa.putalpha(mascara)
    return capa


def pintar(fondo_arriba, fondo_abajo, particula, nucleo, nucleo_alfa, especular_alfa,
           rotacion=1.7, alfa_k=1.15) -> Image.Image:
    lado = LADO * SUPER
    base = vertical(lado, fondo_arriba, fondo_abajo)
    cx = cy = lado / 2
    radio = lado * RADIO_REL

    # El núcleo: sin él, al reducirse a 29–40 pt las partículas se promedian con el fondo y el
    # orbe se deshace en ruido. Con él, los tamaños chicos leen como materia. Va suave en el
    # limbo (caída 0.9) para que el borde siga siendo de partículas, no un círculo recortado.
    nucleo_capa = disco_suave(lado, cx, cy, radio * 0.99, nucleo, nucleo_alfa, plano=0.86)
    base.paste(nucleo_capa, (0, 0), nucleo_capa)

    capa = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    d = ImageDraw.Draw(capa)
    for i, (dx, dy, dz) in enumerate(direcciones(N)):
        px = dx * math.cos(rotacion) + dz * math.sin(rotacion)
        pz = -dx * math.sin(rotacion) + dz * math.cos(rotacion)
        sx = cx + px * radio
        sy = cy + dy * radio * APLASTAMIENTO
        prof = (pz + 1) / 2                              # 0 atrás … 1 al frente
        tam = (0.7 + prof * 1.5) * (radio / 56)          # la misma ley que en Swift
        alfa = min(1.0, (0.15 + prof * 0.5) * alfa_k)
        d.ellipse([sx - tam, sy - tam, sx + tam, sy + tam],
                  fill=(*particula, round(255 * alfa)))

    base.paste(capa, (0, 0), capa)

    # El especular: la misma luz arriba-a-la-izquierda que corona al orbe del héroe. Va ENCIMA
    # de las partículas, como el reflejo que es, y con una caída pronunciada para que sea un
    # brillo y no un velo.
    esp = disco_suave(lado, cx - radio * 0.38, cy - radio * 0.42, radio * 0.60,
                      (255, 255, 255), especular_alfa, plano=0.0)
    base.paste(esp, (0, 0), esp)
    # Sin canal alfa: la App Store rechaza íconos con transparencia.
    return base.resize((LADO, LADO), Image.LANCZOS).convert("RGB")


def main() -> None:
    variantes = {
        # Claro: las partículas verde-tinta (#10694E) sobre el blanco de la app.
        "icon-light-1024.png": dict(
            fondo_arriba=(0xFE, 0xFE, 0xFD), fondo_abajo=(0xF0, 0xF1, 0xEE),
            particula=(0x0B, 0x4C, 0x38), nucleo=(0x3E, 0x94, 0x74),
            nucleo_alfa=0.60, especular_alfa=0.26),
        # Oscuro: el mismo orbe, con el verde iluminado para sostenerse sobre negro.
        "icon-dark-1024.png": dict(
            fondo_arriba=(0x23, 0x25, 0x24), fondo_abajo=(0x10, 0x12, 0x11),
            particula=(0x3C, 0xC9, 0x93), nucleo=(0x14, 0x5B, 0x43),
            nucleo_alfa=0.78, especular_alfa=0.16),
        # Tinted: monocromo sobre negro — iOS le pone el color, nosotros la luminancia.
        "icon-tinted-1024.png": dict(
            fondo_arriba=(0x00, 0x00, 0x00), fondo_abajo=(0x00, 0x00, 0x00),
            particula=(0xF2, 0xF3, 0xF1), nucleo=(0x74, 0x77, 0x72),
            nucleo_alfa=0.80, especular_alfa=0.14),
    }
    # El Watch usa la variante OSCURA: su parrilla de apps es negra, así que el orbe iluminado
    # sobre fondo hondo es el que se lee ahí — no el claro, que ahí sería una mancha blanca.
    salidas = [(DESTINO / n, cfg) for n, cfg in variantes.items()]
    salidas.append((DESTINO_WATCH / "icon-watch-1024.png", variantes["icon-dark-1024.png"]))
    for ruta, cfg in salidas:
        ruta.parent.mkdir(parents=True, exist_ok=True)
        img = pintar(**cfg)
        img.save(ruta, "PNG", optimize=True)
        print(f"{ruta.parent.parent.parent.parent.name}/{ruta.name}  "
              f"{img.size[0]}×{img.size[1]}  modo {img.mode}")


if __name__ == "__main__":
    main()
