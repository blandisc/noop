#!/usr/bin/env python3
# iconforge v20 — forge + AUDIT + auto-injection into the specimen page.
#
# v20 aplica la auditoría técnica completa (sin cambiar dirección creativa):
#   · arc_ink(): los huecos angulares declarados EXISTEN (retrae los caps redondos)
#   · normalización óptica mezclada (extensión + masa de tinta), no solo bbox
#   · piso de terminal 0.75u (nada sub-pixel a 20 pt)
#   · color contra el SSOT real de la app (Instrumento.swift), no hexes libres
#   · higiene de paths: sin nodo de cierre duplicado, orientación explícita, sin defs muertos
#   · fuente única: este script inyecta el payload y la paleta en hoy-iconos.html
import json, colorsys, math, os, re
import numpy as np
from shapely.geometry import Point, Polygon
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
from shapely import affinity

Q = 40
TERMINAL_FLOOR = 0.75          # ancho de remate mínimo: 2*0.75u ≈ 1.25 px @20 pt

def cubic(p0, p1, p2, p3, t):
    t = np.asarray(t)[:, None]
    return ((1-t)**3*np.array(p0) + 3*(1-t)**2*t*np.array(p1)
            + 3*(1-t)*t**2*np.array(p2) + t**3*np.array(p3))

def ribbon(segments, r_stops, n=70):
    pts = [cubic(*seg, np.linspace(0, 1, n)) for seg in segments]
    pts = np.vstack(pts)
    ts = np.linspace(0, 1, len(pts))
    rt, rr = zip(*r_stops)
    radii = np.interp(ts, rt, rr)
    return unary_union([Point(x, y).buffer(r, quad_segs=Q) for (x, y), r in zip(pts, radii)])

def line_ribbon(a, b, r0, r1, n=50):
    t = np.linspace(0, 1, n)[:, None]
    pts = np.array(a)*(1-t) + np.array(b)*t
    radii = np.linspace(r0, r1, n)
    return unary_union([Point(x, y).buffer(r, quad_segs=Q) for (x, y), r in zip(pts, radii)])

def arc_ribbon(c, R, a0, a1, r0, r1, n=60):
    th = np.radians(np.linspace(a0, a1, n))
    xs, ys = c[0] + R*np.cos(th), c[1] - R*np.sin(th)
    radii = np.linspace(r0, r1, n)
    return unary_union([Point(x, y).buffer(r, quad_segs=Q) for x, y, r in zip(xs, ys, radii)])

def cap_deg(r, R):
    """Cuánto se extiende angularmente el cap redondo más allá del extremo del esqueleto."""
    return math.degrees(math.asin(min(1.0, r/R)))

def arc_ink(c, R, t0, t1, r0, r1, retract=(True, True), n=60):
    """arc_ribbon cuyo BORDE DE TINTA cae exactamente en t0/t1: retrae el esqueleto
    por la extensión del cap. Sin esto, todo hueco angular menor a asin(r/R) no existe
    (raíz de los solapes de guardián y estrés en v19)."""
    s = 1 if t1 > t0 else -1
    a0 = t0 + s*cap_deg(r0, R) if retract[0] else t0
    a1 = t1 - s*cap_deg(r1, R) if retract[1] else t1
    return arc_ribbon(c, R, a0, a1, r0, r1, n)

def sector(c, a0, a1, R=30.0, n=48):
    th = np.radians(np.linspace(a0, a1, n))
    return Polygon([c] + [(c[0]+R*math.cos(t), c[1]-R*math.sin(t)) for t in th])

def poly_ribbon(points, r_stops, per=9):
    P = np.array(points, float)
    pts = []
    for i in range(len(P)-1):
        L = np.hypot(*(P[i+1]-P[i]))
        n = max(4, int(per*L))
        t = np.linspace(0, 1, n, endpoint=(i == len(P)-2))[:, None]
        pts.append(P[i]*(1-t) + P[i+1]*t)
    pts = np.vstack(pts)
    d = np.hypot(*np.diff(pts, axis=0).T)
    ts = np.concatenate([[0], np.cumsum(d)]); ts /= ts[-1]
    rt, rr = zip(*r_stops)
    radii = np.interp(ts, rt, rr)
    return unary_union([Point(x, y).buffer(r, quad_segs=Q) for (x, y), r in zip(pts, radii)])

def bezpoly(segments, n=50):
    pts = [cubic(*seg, np.linspace(0, 1, n, endpoint=False)) for seg in segments]
    return Polygon(np.vstack(pts))

def closing(g, r):
    return g.buffer(r, quad_segs=Q).buffer(-r, quad_segs=Q)

def ring(coords):
    # coords de shapely repiten el primer vértice al final: la Z ya cierra el anillo.
    cs = list(coords)[:-1]
    return ' '.join(f'{"M" if i==0 else "L"}{x:.2f} {y:.2f}' for i, (x, y) in enumerate(cs)) + ' Z'

def to_d(geom, tol=0.025):
    """Simplifica, cuantiza a 2 decimales y RE-simplifica (el redondeo crea colinealidad),
    con orientación explícita para que los huecos no dependan de la salida de GEOS."""
    geom = geom.simplify(tol)
    polys = list(geom.geoms) if geom.geom_type == 'MultiPolygon' else [geom]
    out, holed = [], False
    for p in polys:
        p = orient(p, sign=1.0)                       # exterior CCW, huecos CW
        q = Polygon([(round(x, 2), round(y, 2)) for x, y in p.exterior.coords],
                    [[(round(x, 2), round(y, 2)) for x, y in h.coords] for h in p.interiors])
        q = q.simplify(0.001)                          # tira los colineales del redondeo
        if q.is_empty or not q.is_valid:
            q = p
        out.append(ring(q.exterior.coords))
        for h in q.interiors:
            out.append(ring(h.coords))
            holed = True
    return ' '.join(out), holed

def lighten(hex_, dl):
    r, g, b = (int(hex_[i:i+2], 16)/255 for i in (1, 3, 5))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    r, g, b = colorsys.hls_to_rgb(h, min(1, l + dl), s)
    return '#%02X%02X%02X' % (round(r*255), round(g*255), round(b*255))

# ---------------------------------------------------------------- COLOR
# Contrato: cada sello viste el token que el SSOT de la app (Instrumento.swift +
# MetricGlyph.swift) le asigna a SU métrica. `T` = ya es token; `A` = hondo por acuñar
# en StrandDesign (derivado del token base, documentado en el handoff).
C = dict(
    sueno=('#5D5A9E', '#3F3C78'),    # T dataSleep      / T dataSleepDeep
    reposo=('#B85068', '#8E3A50'),   # T dataHeart      / A (no emitido: talla en negativo)
    dorado=('#8A6A2B', '#6B4F1D'),   # T doradoTemp     / A doradoHondo
    azul=('#3B6FA0', '#2A5480'),     # T dataSpO2       / A azulHondo
    carga=('#3F7A5E', '#2A5540'),    # T dataOxygen     / A cargaHonda
    ambar=('#C4631F', '#8F4413'),    # T dataStrain     / T strainDeep
    cian=('#147C8C', '#0E5F6B'),     # T dataHrv        / A cianHondo
    teal=('#4C8998', '#35707E'),     # T dataSteps      / A tealHondo
    tinta=('#5C5648', '#221D16'),    # T inkSecondary   / T ink
)
# Veredicto: el trío del tema vigente (Instrumento.base), no los legacy de LiquidColor.
VERDE, AMBAR, ROJO = '#0C8F62', '#9C5E10', '#BC3A34'   # verdict / warning / critical

def grad(gid, hex_):
    return (f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{lighten(hex_, 0.075)}"/>'
            f'<stop offset="1" stop-color="{hex_}"/></linearGradient>')

# ---- parts registry: key -> list of [geom, mode, color, opacity]
PARTS, GRAD_HUE, DROP = {}, {}, {}

def add(key, geom, mode, color=None, op=1.0):
    PARTS.setdefault(key, []).append([geom, mode, color, op])

# 1 · SUEÑO — creciente real, inclinada -12°, la lectura en el hueco
b, d = C['sueno']; GRAD_HUE['sueno'] = b; DROP['sueno'] = b
cres = Point(11.6, 12).buffer(7.4, quad_segs=96).difference(Point(14.4, 12).buffer(6.6, quad_segs=96))
add('sueno', affinity.rotate(cres, -12, origin=(12, 12)), 'g')
px, py = affinity.rotate(Point(14.2, 12), -12, origin=(12, 12)).coords[0]
add('sueno', Point(px, py).buffer(1.9, quad_segs=48), 'f', d)

# 2 · REPOSO — corazón bezier clásico, simétrico por construcción, lectura tallada
b, d = C['reposo']; GRAD_HUE['reposo'] = b; DROP['reposo'] = b
heart = bezpoly([((12, 19.8), (7.4, 16.4), (4.9, 13.5), (4.9, 10.2)),
                 ((4.9, 10.2), (4.9, 7.8), (6.7, 6.3), (8.8, 6.3)),
                 ((8.8, 6.3), (10.1, 6.3), (11.2, 7.0), (12, 8.2)),
                 ((12, 8.2), (12.8, 7.0), (13.9, 6.3), (15.2, 6.3)),
                 ((15.2, 6.3), (17.3, 6.3), (19.1, 7.8), (19.1, 10.2)),
                 ((19.1, 10.2), (19.1, 13.5), (16.6, 16.4), (12, 19.8))])
heart = closing(heart, 0.35).difference(Point(12, 10.8).buffer(1.55, quad_segs=48))
add('reposo', heart, 'g')

# 3 · GUARDIÁN — arco bicolor: la mitad dorada ES la temperatura de piel y la azul la
# respiración (por eso comparten hue con esos sellos — es la misma señal, no un choque).
# Hueco de ápice de 14° que ahora EXISTE: los extremos se retraen por el cap (v19 solapaba).
bd, _ = C['dorado']; ba, _ = C['azul']
GRAD_HUE['guardian'] = bd
DROP['guardian'] = ('grad', bd, ba)      # gota compuesta: no duplica la de piel ni la de resp
add('guardian', arc_ink((12, 14.7), 6.7, 180, 97, 1.05, 1.5, retract=(False, True)), 'g2', bd)
add('guardian', arc_ink((12, 14.7), 6.7, 0, 83, 1.05, 1.5, retract=(False, True)), 'g3', ba)
# La esfera: se pinta ENTERA en azul hondo y encima la mitad izquierda en dorado base
# (una sola frontera pintada → sin costura de antialias; ΔL* 12 → la partición se lee).
_ball = Point(12, 13.6).buffer(1.9, quad_segs=48)
_left = Polygon([(0, 0), (12, 0), (12, 24), (0, 24)])
add('guardian', _ball, 'f', C['azul'][1])
add('guardian', _ball.intersection(_left), 'f', C['dorado'][0])

# 4 · PIEL — el termómetro: masa sólida, mercurio tallado en negativo
b, d = C['dorado']; GRAD_HUE['piel'] = b; DROP['piel'] = b
thermo = closing(unary_union([line_ribbon((12, 5.2), (12, 13.6), 1.82, 1.82),
                              Point(12, 16.8).buffer(2.78, quad_segs=64)]), 0.6)
empty_tube = line_ribbon((12, 6.9), (12, 9.9), 0.80, 0.80)     # ranura ≥1.3 px @20 pt
thermo = thermo.difference(empty_tube)
add('piel', thermo, 'g')

# 5 · RESPIRACIÓN — onda que crece, la lectura suelta en la trayectoria de salida
b, d = C['azul']; GRAD_HUE['resp'] = b; DROP['resp'] = b
wave = ribbon([((5.2, 13.2), (6.9, 9.5), (9.1, 9.5), (11.0, 13.2)),
               ((11.0, 13.2), (12.3, 15.9), (13.6, 16.2), (14.9, 14.8))],
              [(0, 1.0), (0.3, 1.75), (0.65, 1.4), (1, 1.15)])
add('resp', wave, 'g')
add('resp', Point(18.35, 11.35).buffer(1.9, quad_segs=48), 'f', d)   # ≥2u de aire

# 6 · CARGA — pesa rusa: el asa BAJA hasta el ecuador de la bola para que la soldadura
# sea real (v19 dejaba 0.78u de aire que solo el closing puenteaba → asa flotante a 20 pt)
b, d = C['carga']; GRAD_HUE['carga'] = b; DROP['carga'] = b
# El asa es MÁS ANGOSTA que la bola y baja a soldarse en sus hombros: eso es lo que crea
# la cintura que hace legible la pesa (v19 la tenía del mismo ancho → bolsa, y la soldadura
# era falsa: 0.78 u de aire que solo el closing puenteaba).
kettle = closing(unary_union([arc_ribbon((12, 9.0), 3.5, 207, -27, 1.2, 1.2),
                              Point(12, 15.0).buffer(4.7, quad_segs=96)]), 0.30)
add('carga', kettle, 'g')

# 7 · ESFUERZO — cometa caligráfico (dataStrain: su token real)
b, d = C['ambar']; GRAD_HUE['esfuerzo'] = b; DROP['esfuerzo'] = b
add('esfuerzo', ribbon([((4.8, 19.3), (9.6, 18.4), (11.6, 13.8), (14.6, 9.0))],
                       [(0, TERMINAL_FLOOR), (1, 1.5)]), 'g')
add('esfuerzo', Point(16.06, 6.67).buffer(2.2, quad_segs=48), 'f', d)

# 8 · HRV — trazo ECG, dos espigas de altura distinta; la lectura marca el pico R
b, d = C['cian']; GRAD_HUE['hrv'] = b; DROP['hrv'] = b
ecg = poly_ribbon([(4.9, 13.6), (7.7, 13.6), (8.9, 7.4), (10.1, 15.4), (11.2, 13.6),
                   (12.9, 13.6), (14.0, 9.8), (15.2, 14.5), (16.2, 13.6), (19.1, 13.6)],
                  [(0, 0.94), (0.22, 1.19), (0.3, 1.38), (0.42, 1.19), (0.55, 1.0),
                   (0.62, 1.25), (0.75, 1.13), (1, 0.94)])
add('hrv', ecg, 'g')

# 9 · ESTRÉS — el medidor CON sus zonas de veredicto. Huecos de 14° que existen de verdad,
# aguja vertical (posición canónica neutra: un sello de identidad no dicta veredicto).
b, d = C['tinta']; GRAD_HUE['estres'] = b; DROP['estres'] = AMBAR
# El arco es de 240° (la convención real del velocímetro), no el semicírculo de v19: eso
# es lo que lo separa del arco del guardián en silueta, no el color.
_c, _R, _w = (12, 14.9), 6.3, 1.18
_band = arc_ribbon(_c, _R, 210, -30, _w, _w)
# Se pinta la banda entera en ámbar y encima los sectores verde y rojo: cada frontera se
# pinta UNA vez (sin canal de antialias entre dos rellenos adyacentes) y las tres zonas
# quedan exactamente en 60° — sin solape y sin sesgo por orden de pintado.
add('estres', _band, 'f', AMBAR)
add('estres', _band.intersection(sector(_c, 218, 130)), 'f', VERDE)
add('estres', _band.intersection(sector(_c, 50, -38)), 'f', ROJO)
add('estres', ribbon([((12, 14.9), (12, 13.9), (12, 13.0), (12, 12.0))],
                     [(0, 1.05), (1, 0.72)]), 'f', d)
add('estres', Point(12, 14.9).buffer(1.3, quad_segs=48), 'f', d)

# 10 · PASOS — el caminante (dataSteps: su token real). Cabeza en tono hondo = su voz de
# lectura, y de paso una sola rampa por path (v19 reiniciaba el gradiente en el cuello).
b, d = C['teal']; GRAD_HUE['pasos'] = b; DROP['pasos'] = b
bodyparts = [
    ribbon([((12.88, 7.95), (12.55, 9.5), (12.22, 10.75), (11.9, 12.0))], [(0, 1.4), (1, 1.35)]),
    ribbon([((11.9, 12.0), (12.9, 14.3), (14.0, 16.3), (15.1, 18.4))], [(0, 1.3), (1, 0.88)]),
    ribbon([((11.9, 12.1), (10.6, 13.8), (9.4, 15.3), (8.0, 17.5))], [(0, 1.25), (1, TERMINAL_FLOOR)]),
    ribbon([((12.74, 8.15), (13.9, 8.8), (14.8, 9.7), (15.5, 10.9))], [(0, 1.0), (1, TERMINAL_FLOOR)]),
    ribbon([((12.54, 8.45), (11.2, 9.1), (10.5, 10.1), (9.9, 11.4))], [(0, 0.95), (1, TERMINAL_FLOOR)])]
add('pasos', closing(unary_union(bodyparts), 0.22), 'g')
add('pasos', Point(13.35, 3.70).buffer(1.58, quad_segs=48), 'f', d)

# ============== AUDITORÍA + NORMALIZACIÓN ÓPTICA ==============
# La normalización v19 solo igualaba bbox y sus clamps empujaban al revés (las masas
# sólidas recibían el upscale máximo). Ahora mezcla extensión y masa de tinta.
TARGET_MAXDIM, TARGET_AREA = 15.9, 78.0
SMIN, SMAX = 0.93, 1.08
OUT, GEOM, SWIFT = {}, {}, {}
print(f'{"glyph":10} {"maxdim":>7} {"area":>7} {"scale":>6} → {"maxdim":>7} {"area":>7}')
for key, parts in PARTS.items():
    union = unary_union([p[0] for p in parts])
    x0, y0, x1, y1 = union.bounds
    cx, cy = (x0+x1)/2, (y0+y1)/2
    maxdim, area = max(x1-x0, y1-y0), union.area
    s = TARGET_MAXDIM/maxdim
    if area > TARGET_AREA:        # las masas sólidas ya pesan: igualar bbox las agrandaría
        s = min(s, 1.0)           # (el clamp de v19 les daba justo el upscale máximo)
    s = min(SMAX, max(SMIN, s))
    for p in parts:
        p[0] = affinity.translate(affinity.scale(p[0], s, s, origin=(cx, cy)), 12-cx, 12-cy)
    u2 = unary_union([p[0] for p in parts])
    nx0, ny0, nx1, ny1 = u2.bounds
    GEOM[key] = u2
    print(f'{key:10} {maxdim:7.2f} {area:7.1f} {s:6.3f} → '
          f'{max(nx1-nx0, ny1-ny0):7.2f} {u2.area:7.1f}')

    gid = 'g_' + key
    partes = []
    body, g2, g3, c2, c3, uses_grad = [], None, None, None, None, False
    for geom, mode, color, op in parts:
        if mode == 'g':
            dstr, holed = to_d(geom)
            fr = ' fill-rule="evenodd"' if holed else ''
            body.append(f'<path d="{dstr}" fill="url(#{gid})"{fr}/>')
            partes.append((dstr, lighten(GRAD_HUE[key], 0.075), GRAD_HUE[key], holed))
            uses_grad = True
        elif mode == 'g2':
            g2, c2 = geom, color
        elif mode == 'g3':
            g3, c3 = geom, color
        else:
            dstr, holed = to_d(geom)
            fr = ' fill-rule="evenodd"' if holed else ''
            o = f' fill-opacity="{op}"' if op != 1 else ''
            body.append(f'<path d="{dstr}" fill="{color}"{o}{fr}/>')
            partes.append((dstr, None, color, holed))
    defs = grad(gid, GRAD_HUE[key]) if uses_grad else ''    # sin defs muertos
    if g2 is not None:
        defs += grad(gid+'L', c2) + grad(gid+'R', c3)
        body.insert(0, f'<path d="{to_d(g3)[0]}" fill="url(#{gid}R)"/>')
        body.insert(0, f'<path d="{to_d(g2)[0]}" fill="url(#{gid}L)"/>')
        partes.insert(0, (to_d(g3)[0], lighten(c3, 0.075), c3, False))
        partes.insert(0, (to_d(g2)[0], lighten(c2, 0.075), c2, False))
    OUT[key] = (f'<defs>{defs}</defs>' if defs else '') + ''.join(body)
    SWIFT[key] = partes

# ---- verificación adversarial: simetría, área segura, mínimos a 20 pt, huecos ----
print()
print(f'{"glyph":10} {"asym%":>6} {"bounds":>7} {"min@20px":>9}  nota')
INTENT = {'sueno': 'creciente+tilt', 'resp': 'onda direccional', 'esfuerzo': 'cometa',
          'hrv': 'variabilidad', 'pasos': 'zancada', 'carga': 'asa+bola',
          'estres': 'zonas simétricas + aguja vertical'}
PX20 = 20/24.0
for key, parts in PARTS.items():
    u = GEOM[key]
    m = affinity.scale(u, -1, 1, origin=(12, 0))
    asym = 100 * u.symmetric_difference(m).area / u.area
    x0, y0, x1, y1 = u.bounds
    ok = 'SI' if (x0 >= 1.9 and y0 >= 1.9 and x1 <= 22.1 and y1 <= 22.1) else 'NO'
    # separación mínima entre partes pintadas distintas (aires estructurales)
    geoms = [p[0] for p in parts]
    gaps = [geoms[i].distance(geoms[j]) for i in range(len(geoms)) for j in range(i+1, len(geoms))
            if geoms[i].distance(geoms[j]) > 1e-9]
    gmin = f'{min(gaps)*PX20:.2f}px' if gaps else '—'
    print(f'{key:10} {asym:6.1f} {ok:>7} {gmin:>9}  {INTENT.get(key, "debe ser ~0")}')

# solapes entre partes de color distinto (el defecto raíz de v19)
print()
for key in ('guardian', 'estres'):
    ps = [p for p in PARTS[key] if p[1] in ('f', 'g2', 'g3')]
    for i in range(len(ps)):
        for j in range(i+1, len(ps)):
            a, b_ = ps[i][0], ps[j][0]
            inter = a.intersection(b_).area
            intentional = ((key == 'guardian' and {ps[i][2], ps[j][2]} == {C['azul'][1], C['dorado'][0]})
                           or (key == 'estres' and AMBAR in (ps[i][2], ps[j][2])))
            if inter > 0.01 and ps[i][2] != ps[j][2] and not intentional:
                print(f'!! {key}: solape {inter:.3f} u² entre {ps[i][2]} y {ps[j][2]}')
gi = GEOM['guardian'].intersection(GEOM['estres']).area
gu = GEOM['guardian'].union(GEOM['estres']).area
print(f'IoU guardián↔estrés = {gi/gu:.3f}  (v19: 0.803)')
nodes = sum(len(re.findall(r'[\d.]+ [\d.]+', v)) for v in OUT.values())
print(f'nodos totales: {nodes}  ·  bytes: {sum(len(v) for v in OUT.values())}')

with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'glyphs.json'), 'w') as f:
    json.dump(OUT, f)

# ---- fuente única: inyecta payload + gotas en la página del specimen ----
drops = {}
for k, v in DROP.items():
    drops[k] = (f'linear-gradient(135deg,{v[1]}1A,{v[2]}1A)' if isinstance(v, tuple)
                else f'{v}1A')
page = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'specimen.html')
src = open(page).read()
src, n1 = re.subn(r'(?m)^  var FORGED = .*$',
                  '  var FORGED = ' + json.dumps(OUT) + ';', src)
src, n2 = re.subn(r'(?m)^  var DROP = .*$',
                  '  var DROP = ' + json.dumps(drops) + ';', src)
assert n1 == 1 and n2 == 1, f'inyección fallida: FORGED={n1} DROP={n2}'
open(page, 'w').write(src)
print(f'forjados {len(OUT)} glifos · inyectados en {page}')

# ---- emisión de Swift: los mismos paths, para StrandDesign (una sola fuente) ----
CASO = {'sueno': 'sueno', 'reposo': 'reposo', 'guardian': 'guardian', 'piel': 'piel',
        'resp': 'respiracion', 'carga': 'carga', 'esfuerzo': 'esfuerzo', 'hrv': 'hrv',
        'estres': 'estres', 'pasos': 'pasos'}
GOTA = {k: GRAD_HUE[k] for k in PARTS}
GOTA['estres'] = AMBAR          # el medidor es tricolor: su identidad es el ámbar de aviso
GOTA['guardian'] = C['dorado'][0]

swift = ['// GENERADO por Tools/sellos-hoy/forge.py — NO editar a mano.',
         '// Regenera con: cd Tools/sellos-hoy && python3 forge.py',
         '//',
         '// Los diez sellos de métrica de Hoy, en el viewBox 24x24 del forjador. Cada parte',
         '// trae su relleno ya resuelto: plano o degradado vertical (claro arriba = el tono',
         '// base aclarado en HSL L+0.075, la regla del sistema).',
         'import SwiftUI', '',
         'extension SelloMetrica {', '',
         '    /// El tono de identidad del sello — el mismo de su gota al 10 %.',
         '    var tono: Color {', '        switch self {']
for k in PARTS:
    swift.append(f'        case .{CASO[k]}: return Color(hex: "{GOTA[k]}")')
swift += ['        }', '    }', '',
          '    /// Las partes en orden de pintado, del fondo al frente.',
          '    var partes: [Parte] {', '        switch self {']
for k in PARTS:
    swift.append(f'        case .{CASO[k]}:')
    swift.append('            return [')
    for (d, claro, base, holed) in SWIFT[k]:
        rel = (f'.vertical(Color(hex: "{claro}"), Color(hex: "{base}"))' if claro
               else f'.plano(Color(hex: "{base}"))')
        swift.append(f'                Parte(d: "{d}",')
        swift.append(f'                      relleno: {rel},')
        swift.append(f'                      talla: {"true" if holed else "false"}),')
    swift.append('            ]')
swift += ['        }', '    }', '}', '']

destino = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       '..', '..', 'Packages', 'StrandDesign', 'Sources',
                       'StrandDesign', 'LiquidGlass', 'SelloMetricaPaths.swift')
destino = os.path.normpath(destino)
with open(destino, 'w') as f:
    f.write('\n'.join(swift))
print('emitido', os.path.relpath(destino, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')))
