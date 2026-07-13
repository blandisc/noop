#!/usr/bin/env python3
"""Construye el muro de estados (docs/appmap/index.html) acomodando las capturas
REALES del simulador (docs/appmap/shots/*.png) en una cuadrícula por flujo.

Filosofía (enfoque B): el PNG ES la pantalla — renderizada por el código real vía
el harness de capturas (CenitUITests/NOOPScreenshotTests + ScreenshotFixtures).
Este script NO redibuja UI; solo la acomoda, etiqueta y hace navegable/compartible.

Regenerar tras capturar estados nuevos:
    python3 Tools/build-appmap.py
"""
import os, html

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = "shots"  # relativo a docs/appmap (rutas del <img>)
OUT = os.path.join(ROOT, "docs", "appmap", "index.html")

# --- Manifiesto: pantalla -> estados (en orden de flujo/ciclo de vida) ---
# cada estado: (archivo_png, título, condición de entrada técnica)
MAP = [
 ("Hoy · TodayView",
  "El hub principal. El héroe nunca miente: numeral a color con veredicto, "
  "«··» calibrando, barra gris sin lectura, tinta cuando hay número sin contexto.",
  [
   ("hoy-vacio.png", "Vacío · primer arranque",
    "sin strap visto y sin base → HeroState .waiting · tarjetas Conectar Apple Salud / Emparejar banda"),
   ("hoy-calibrando.png", "Calibrando",
    "strap visto, ownNights < 4 · overline «TU BASE SE AFINA» · numeral «··» · tiles vacíos"),
   ("hoy-descargando.png", "Descargando la noche",
    "offload en curso (live.backfilling), sin recovery de hoy · «Sincronizando con tu banda…»"),
   ("hoy-apunto.png", "Veredicto · A punto",
    "repo.today.recovery ≠ nil · nivel .primed (good ≥ 2) · numeral en verde de banda"),
   ("hoy-equilibrado.png", "Veredicto · Equilibrado",
    "nivel .balanced (nada notable flagea) · numeral en color de banda"),
   ("hoy-exigido.png", "Veredicto · Exigido",
    "nivel .strained (una señal de recuperación abajo) · numeral ámbar"),
   ("hoy-desgastado.png", "Veredicto · Desgastado",
    "nivel .rundown (≥2 señales abajo a la vez) · numeral rojo"),
   ("hoy-insufficient.png", "Veredicto · Insufficient",
    "hay número de hoy pero sin historia previa → nivel .insufficient · numeral en tinta, sin veredicto"),
  ]),
]

def esc(s): return html.escape(s, quote=True)

def card(shot, title, cond):
    src = f"{SHOTS}/{shot}"
    exists = os.path.exists(os.path.join(ROOT, "docs", "appmap", SHOTS, shot))
    img = (f'<img loading="lazy" src="{src}" alt="{esc(title)}">' if exists
           else f'<div class="missing">falta captura<br>{esc(shot)}</div>')
    return (f'<figure class="card">'
            f'<div class="phone">{img}</div>'
            f'<figcaption><b>{esc(title)}</b><span>{esc(cond)}</span></figcaption>'
            f'</figure>')

def group(name, blurb, states):
    cards = "\n".join(card(*s) for s in states)
    return (f'<section class="group"><header class="gh">'
            f'<h2>{esc(name)}</h2><p>{esc(blurb)}</p>'
            f'<span class="count">{len(states)} estados</span></header>'
            f'<div class="row">{cards}</div></section>')

STYLE = """
*{box-sizing:border-box;margin:0;padding:0}
body{background:#232120;color:#EDE9DF;font-family:'Space Grotesk',system-ui,sans-serif;padding:44px 40px 90px}
a{color:inherit}
.head{max-width:1200px;margin:0 auto 8px}
.head h1{font-size:28px;font-weight:700;letter-spacing:-.5px;color:#fff}
.head p{font-size:14px;color:#A8A196;margin-top:10px;max-width:760px;line-height:1.55}
.head .meta{font-size:12px;color:#7C766B;margin-top:14px}
.head .meta b{color:#B7E3C9;font-weight:600}
.group{max-width:1400px;margin:0 auto;padding:40px 0 8px;border-top:1px solid #3A3733}
.group:first-of-type{border-top:0}
.gh{margin-bottom:22px}
.gh h2{font-size:15px;font-weight:600;letter-spacing:2px;text-transform:uppercase;color:#EDE9DF}
.gh p{font-size:13px;color:#9A9389;margin-top:8px;max-width:820px;line-height:1.5}
.gh .count{display:inline-block;margin-top:10px;font-size:11px;font-weight:600;letter-spacing:1px;color:#7C766B;text-transform:uppercase}
.row{display:flex;flex-wrap:wrap;gap:34px}
.card{width:264px;display:flex;flex-direction:column;gap:12px}
.phone{border-radius:34px;overflow:hidden;background:#000;box-shadow:0 18px 44px rgba(0,0,0,.45);border:1px solid #000;line-height:0}
.phone img{width:100%;display:block}
.missing{aspect-ratio:1206/2622;display:flex;align-items:center;justify-content:center;color:#8a8378;font-size:12px;text-align:center;background:#2c2a28;line-height:1.5}
figcaption b{display:block;font-size:14px;font-weight:600;color:#fff}
figcaption span{display:block;font-size:11.5px;color:#948D82;margin-top:5px;line-height:1.45}
"""

def build():
    groups = "\n".join(group(*g) for g in MAP)
    total = sum(len(g[2]) for g in MAP)
    doc = f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cénit · Mapa de estados (capturas reales)</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>{STYLE}</style></head><body>
<div class="head"><h1>Cénit · Mapa de estados</h1>
<p>Fuente de verdad viva. Cada marco es una <b>captura real del simulador iOS</b> renderizada por el código de la app —no una reconstrucción— vía el harness <code>NOOPScreenshotTests</code> + <code>ScreenshotFixtures</code>. Un marco por estado.</p>
<div class="meta"><b>{total}</b> estados capturados · regenera con <b>python3 Tools/build-appmap.py</b> tras correr el harness.</div></div>
{groups}
</body></html>"""
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w").write(doc)
    print(f"escrito {OUT} · {total} estados")

if __name__ == "__main__":
    build()
