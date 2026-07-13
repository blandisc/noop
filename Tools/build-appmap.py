#!/usr/bin/env python3
"""Construye el mapa de estados (docs/appmap/index.html) como un CANVAS tipo Figma:
nodos = capturas REALES del simulador, conectados por flechas de flujo, con pan + zoom.

Filosofía (enfoque B): el PNG ES la pantalla — renderizada por el código real vía el harness
(CenitUITests/NOOPScreenshotTests + ScreenshotFixtures). Este script NO redibuja UI: la acomoda
en un lienzo navegable, la etiqueta y traza las transiciones entre estados.

Regenerar tras capturar estados nuevos:  python3 Tools/build-appmap.py
El mismo manifiesto genera el Artifact self-contained (Tools/build-appmap-artifact.py).
"""
import os, html, base64

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPMAP = os.path.join(ROOT, "docs", "appmap")

NODE_W = 300                       # ancho de imagen mostrada
IMG_H  = round(NODE_W * 2622/1206) # alto proporcional a la captura (~652)

# --- Manifiesto: grupos (pantallas), cada uno con nodos posicionados y aristas de flujo ---
# node: id -> (png, título, condición, x, y)
# edge: (id_origen, id_destino, etiqueta)
MAP = [
 {
  "name": "Hoy · TodayView",
  "blurb": "El hub principal. El héroe nunca miente: numeral a color con veredicto, «··» calibrando, "
           "barra gris sin lectura, tinta cuando hay número sin contexto.",
  "nodes": {
    "vacio":       ("hoy-vacio.png",       "Vacío · primer arranque",
                    "sin strap visto y sin base → HeroState .waiting · tarjetas Conectar Apple Salud / Emparejar banda", 0, 520),
    "calibrando":  ("hoy-calibrando.png",  "Calibrando",
                    "strap visto, ownNights < 4 · overline «TU BASE SE AFINA» · numeral «··» · tiles vacíos", 460, 520),
    "descargando": ("hoy-descargando.png", "Descargando la noche",
                    "offload en curso (live.backfilling), sin recovery de hoy · «Sincronizando con tu banda…»", 920, 520),
    "apunto":      ("hoy-apunto.png",      "Veredicto · A punto",
                    "nivel .primed (good ≥ 2) · numeral en verde de banda", 1420, 80),
    "exigido":     ("hoy-exigido.png",     "Veredicto · Exigido",
                    "nivel .strained (una señal de recuperación abajo) · numeral ámbar", 1420, 960),
    "equilibrado": ("hoy-equilibrado.png", "Veredicto · Equilibrado",
                    "nivel .balanced (nada notable flagea) · numeral en color de banda", 1860, 80),
    "desgastado":  ("hoy-desgastado.png",  "Veredicto · Desgastado",
                    "nivel .rundown (≥2 señales abajo a la vez) · numeral rojo", 1860, 960),
    "insufficient":("hoy-insufficient.png","Veredicto · Insufficient",
                    "hay número de hoy pero sin historia previa → nivel .insufficient · numeral en tinta, sin veredicto", 2320, 520),
  },
  "edges": [
    ("vacio", "calibrando", "empareja banda"),
    ("calibrando", "descargando", "1ª sincronización"),
    ("descargando", "apunto", "recovery listo"),
    ("descargando", "equilibrado", ""),
    ("descargando", "exigido", ""),
    ("descargando", "desgastado", ""),
    ("descargando", "insufficient", "sin historia previa"),
  ],
 },
]

def esc(s): return html.escape(s, quote=True)

def _anchors(x, y):
    cy = y + IMG_H/2
    return {"r": (x+NODE_W, cy), "l": (x, cy)}

def node_html(nid, png, title, cond, x, y, src):
    return (f'<figure class="node" style="left:{x}px;top:{y}px;width:{NODE_W}px">'
            f'<div class="phone"><img loading="lazy" src="{src}" alt="{esc(title)}"></div>'
            f'<figcaption><b>{esc(title)}</b><span>{esc(cond)}</span></figcaption></figure>')

def edges_svg(nodes, edges):
    # bounding para el lienzo SVG
    maxx = max(x+NODE_W for (_,_,_,x,y) in nodes.values()) + 200
    maxy = max(y+IMG_H+120 for (_,_,_,x,y) in nodes.values()) + 200
    paths = []
    for a, b, label in edges:
        (_,_,_,ax,ay) = nodes[a]; (_,_,_,bx,by) = nodes[b]
        s = _anchors(ax,ay)["r"]; t = _anchors(bx,by)["l"]
        dx = max(80, (t[0]-s[0])*0.45)
        d = f'M {s[0]:.0f} {s[1]:.0f} C {s[0]+dx:.0f} {s[1]:.0f}, {t[0]-dx:.0f} {t[1]:.0f}, {t[0]:.0f} {t[1]:.0f}'
        paths.append(f'<path d="{d}" class="edge"/>')
        if label:
            mx=(s[0]+t[0])/2; my=(s[1]+t[1])/2
            paths.append(f'<g class="elabel" transform="translate({mx:.0f},{my:.0f})">'
                         f'<rect x="-{len(label)*3.3+8:.0f}" y="-11" width="{len(label)*6.6+16:.0f}" height="22" rx="11"/>'
                         f'<text x="0" y="4" text-anchor="middle">{esc(label)}</text></g>')
    return (f'<svg class="edges" width="{maxx}" height="{maxy}">'
            f'<defs><marker id="arw" markerWidth="12" markerHeight="12" refX="9" refY="5" orient="auto">'
            f'<path d="M0 0 L10 5 L0 10 z" fill="#7A8B84"/></marker></defs>{"".join(paths)}</svg>')

def group_html(g, src_of):
    nodes = g["nodes"]
    body = edges_svg(nodes, g["edges"])
    for nid,(png,title,cond,x,y) in nodes.items():
        body += node_html(nid,png,title,cond,x,y, src_of(png))
    maxx = max(x+NODE_W for (_,_,_,x,y) in nodes.values()) + 240
    maxy = max(y+IMG_H+120 for (_,_,_,x,y) in nodes.values()) + 160
    label=(f'<div class="glabel"><h2>{esc(g["name"])}</h2><p>{esc(g["blurb"])}</p>'
           f'<span class="count">{len(nodes)} estados</span></div>')
    return f'<section class="board" style="width:{maxx}px;height:{maxy}px">{label}{body}</section>'

STYLE = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;background:#1E1C1B;font-family:'Space Grotesk',system-ui,sans-serif;color:#EDE9DF}
.topbar{position:fixed;top:0;left:0;right:0;height:58px;z-index:50;display:flex;align-items:center;gap:18px;
  padding:0 22px;background:rgba(24,22,21,.86);backdrop-filter:blur(10px);border-bottom:1px solid #38342F}
.topbar h1{font-size:16px;font-weight:700;color:#fff}
.topbar .sub{font-size:12px;color:#8C857A}
.topbar .spacer{flex:1}
.zoom{display:flex;align-items:center;gap:2px;background:#2A2724;border:1px solid #3C3833;border-radius:10px;padding:3px}
.zoom button{width:30px;height:28px;border:0;background:transparent;color:#CFC9BD;font-size:17px;cursor:pointer;border-radius:7px}
.zoom button:hover{background:#38342F}
.zoom .fit{width:auto;padding:0 12px;font-size:12px;font-weight:600;letter-spacing:.5px}
.hint{position:fixed;bottom:16px;left:50%;transform:translateX(-50%);z-index:50;font-size:11.5px;color:#7A736A;
  background:rgba(24,22,21,.8);padding:6px 14px;border-radius:20px;border:1px solid #38342F}
#vp{position:absolute;inset:58px 0 0 0;overflow:hidden;cursor:grab}
#vp.drag{cursor:grabbing}
#world{position:absolute;top:0;left:0;transform-origin:0 0;will-change:transform}
.board{position:relative;margin:120px 160px}
.glabel{position:absolute;top:-96px;left:0;max-width:760px}
.glabel h2{font-size:14px;font-weight:600;letter-spacing:2px;text-transform:uppercase;color:#EDE9DF}
.glabel p{font-size:12.5px;color:#8C857A;margin-top:7px;line-height:1.5}
.glabel .count{display:inline-block;margin-top:8px;font-size:10.5px;font-weight:600;letter-spacing:1px;color:#6E675E;text-transform:uppercase}
.edges{position:absolute;top:0;left:0;pointer-events:none;overflow:visible}
.edge{fill:none;stroke:#5C6B64;stroke-width:2.5;marker-end:url(#arw)}
.elabel rect{fill:#2A2724;stroke:#4A5450}
.elabel text{fill:#B7C3BD;font-size:11px;font-weight:600;font-family:'Space Grotesk',sans-serif}
.node{position:absolute;margin:0}
.phone{border-radius:34px;overflow:hidden;background:#000;box-shadow:0 16px 40px rgba(0,0,0,.5);border:1px solid #000;line-height:0}
.phone img{width:100%;display:block}
figcaption{margin-top:12px}
figcaption b{display:block;font-size:14px;font-weight:600;color:#fff}
figcaption span{display:block;font-size:11.5px;color:#948D82;margin-top:5px;line-height:1.45}
"""

PANZOOM_JS = """
const vp=document.getElementById('vp'),world=document.getElementById('world');
let s=0.62,tx=80,ty=40,down=false,px=0,py=0;
function apply(){world.style.transform=`translate(${tx}px,${ty}px) scale(${s})`}
function zoomAt(cx,cy,ns){ns=Math.min(2.2,Math.max(0.12,ns));const wx=(cx-tx)/s,wy=(cy-ty)/s;s=ns;tx=cx-wx*s;ty=cy-wy*s;apply()}
vp.addEventListener('wheel',e=>{e.preventDefault();const r=vp.getBoundingClientRect();
  if(e.ctrlKey||e.metaKey){zoomAt(e.clientX-r.left,e.clientY-r.top,s*(e.deltaY<0?1.1:0.9))}
  else{tx-=e.deltaX;ty-=e.deltaY;apply()}},{passive:false});
vp.addEventListener('pointerdown',e=>{down=true;px=e.clientX;py=e.clientY;vp.classList.add('drag');vp.setPointerCapture(e.pointerId)});
vp.addEventListener('pointermove',e=>{if(!down)return;tx+=e.clientX-px;ty+=e.clientY-py;px=e.clientX;py=e.clientY;apply()});
vp.addEventListener('pointerup',e=>{down=false;vp.classList.remove('drag')});
function fit(){const b=world.getBoundingClientRect(),r=vp.getBoundingClientRect();
  const cw=world.scrollWidth,ch=world.scrollHeight;s=Math.min(r.width/cw,r.height/ch)*0.92;
  tx=(r.width-cw*s)/2;ty=(r.height-ch*s)/2;apply()}
document.getElementById('zin').onclick=()=>{const r=vp.getBoundingClientRect();zoomAt(r.width/2,r.height/2,s*1.2)};
document.getElementById('zout').onclick=()=>{const r=vp.getBoundingClientRect();zoomAt(r.width/2,r.height/2,s*0.83)};
document.getElementById('fit').onclick=fit;
window.addEventListener('load',()=>setTimeout(fit,60));apply();
"""

def render(src_of, font_css="", total_note=""):
    boards = "".join(group_html(g, src_of) for g in MAP)
    total = sum(len(g["nodes"]) for g in MAP)
    return f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cénit · Mapa de estados</title>{font_css}
<style>{STYLE}</style></head><body>
<div class="topbar"><h1>Cénit · Mapa de estados</h1>
<span class="sub">capturas reales del simulador · {total} estados{total_note}</span>
<span class="spacer"></span>
<div class="zoom"><button id="zout">−</button><button id="zin">+</button><button class="fit" id="fit">Ajustar</button></div></div>
<div id="vp"><div id="world">{boards}</div></div>
<div class="hint">Arrastra para mover · rueda para desplazar · ⌘/Ctrl + rueda para zoom</div>
<script>{PANZOOM_JS}</script></body></html>"""

# --- Puente captura→shots: nombre del PNG en shots/ -> nombre crudo que escribe el harness ---
# (el harness usa today_<estado>.png; el muro usa hoy-<estado>.png). Extender por pantalla.
SHOT_SRC = {
    "hoy-vacio.png":        "today.png",
    "hoy-calibrando.png":   "today_calibrating.png",
    "hoy-descargando.png":  "today_downloading.png",
    "hoy-insufficient.png": "today_insufficient.png",
    "hoy-apunto.png":       "today_primed.png",
    "hoy-equilibrado.png":  "today_balanced.png",
    "hoy-exigido.png":      "today_strained.png",
    "hoy-desgastado.png":   "today_rundown.png",
}
SHOT_W = 800   # ancho al que se reescalan las capturas para el repo/muro (nítido, ligero)

def sync_shots(staging_dir):
    """Copia+reescala los PNG crudos del harness (staging_dir) a docs/appmap/shots/ con el
    nombre del muro y a SHOT_W de ancho. Devuelve (copiados, faltantes)."""
    import shutil, subprocess
    dst = os.path.join(APPMAP, "shots"); os.makedirs(dst, exist_ok=True)
    copied, missing = [], []
    for shot, raw in SHOT_SRC.items():
        src = os.path.join(staging_dir, raw)
        if not os.path.exists(src): missing.append(raw); continue
        out = os.path.join(dst, shot)
        shutil.copyfile(src, out)
        subprocess.run(["sips", "--resampleWidth", str(SHOT_W), out],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        copied.append(shot)
    print(f"sync_shots: {len(copied)} copiados a {SHOT_W}px" + (f" · faltan {missing}" if missing else ""))
    return copied, missing

def build_served():
    css=('<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
         '<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">')
    doc=render(lambda png: f"shots/{png}", css)
    open(os.path.join(APPMAP,"index.html"),"w").write(doc)
    print("escrito docs/appmap/index.html ·", sum(len(g['nodes']) for g in MAP),"estados")

if __name__ == "__main__":
    build_served()
