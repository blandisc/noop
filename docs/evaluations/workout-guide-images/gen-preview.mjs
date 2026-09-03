import { readFileSync, existsSync, writeFileSync } from "node:fs";
const A = "/home/user/bryllim/workout-guide/packages/workout-guide/assets";
const load = (slug, frame=1) => {
  const p = `${A}/${slug}/frame-${frame}.svg`;
  if (!existsSync(p)) return null;
  return readFileSync(p,"utf8").replace(/fill="#fff"/g,'fill="currentColor"').replace(/<\?xml.*?\?>/,"").trim();
};

// Curated, movement-correct rows (avoid the fuzzy false-positives)
const EMBER="#C4631F", TEAL="#3E7F8C", INDIGO="#5D5A9E";
const rows = [
  {slug:"incline-dumbbell-press", name:"Press inclinado con mancuerna", sub:"Pecho · Mancuerna", fam:EMBER},
  {slug:"push-up",                name:"Lagartija",                     sub:"Pecho · Peso corporal", fam:EMBER},
  {slug:"arnold-press",           name:"Press Arnold",                  sub:"Hombros · Mancuerna", fam:EMBER},
  {slug:"face-pull",              name:"Face pull",                     sub:"Espalda alta · Polea", fam:TEAL},
  {slug:"one-arm-dumbbell-row",   name:"Remo a una mano",               sub:"Dorsal · Mancuerna", fam:TEAL},
  {slug:"romanian-deadlift",      name:"Peso muerto rumano",            sub:"Isquiotibiales · Barra", fam:INDIGO},
];
const hero = {slug:"romanian-deadlift", name:"Peso muerto rumano", sub:"Isquiotibiales · Barra · peso×reps", fam:INDIGO};

for (const r of rows) { r.svg = load(r.slug); if(!r.svg) console.error("MISSING", r.slug); }
const heroFrames = [1,2,3].map(f=>load(hero.slug,f));

const rowHTML = rows.map(r=>`
  <div class="row">
    <div class="tile" style="border-color:${r.fam}">
      <div class="glyph">${r.svg||""}</div>
    </div>
    <div class="rowtext">
      <div class="rowname">${r.name}</div>
      <div class="rowsub">${r.sub}</div>
    </div>
    <div class="chev">›</div>
  </div>`).join('\n<div class="hair"></div>\n');

const heroStrip = heroFrames.map((s,i)=>`<div class="frame" style="color:${hero.fam}"><div class="glyph">${s||""}</div><div class="framelbl">${["reposo","medio","contracción"][i]}</div></div>`).join("");

const html = `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cénit · siluetas de ejercicio (spike)</title>
<style>
:root{--paper:#F4F1E8;--surface:#FBF9F2;--hair:#E6E0D2;--hairS:#D8D0BD;--ink:#221D16;--ink2:#5A5347;--ink3:#8B8372;}
*{box-sizing:border-box;margin:0;padding:0}
body{background:#E7E1D3;font-family:Georgia,'Times New Roman',serif;color:var(--ink);padding:28px 14px;-webkit-font-smoothing:antialiased}
.phone{max-width:390px;margin:0 auto 26px;background:var(--paper);border-radius:34px;padding:22px 18px 26px;box-shadow:0 18px 50px rgba(40,32,20,.18);border:1px solid var(--hairS)}
.grotesk{font-family:'Space Grotesk',ui-sans-serif,system-ui,sans-serif}
.kicker{font-family:'Space Grotesk',ui-sans-serif,system-ui,sans-serif;font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:var(--ink3);font-weight:600}
.search{margin:14px 0 6px;background:var(--surface);border:1px solid var(--hairS);border-radius:12px;padding:11px 13px;color:var(--ink3);font-size:15px;display:flex;gap:8px;align-items:center}
.band{font-family:'Space Grotesk',ui-sans-serif,system-ui,sans-serif;font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--ink3);font-weight:600;margin:18px 2px 6px;display:flex;justify-content:space-between}
.row{display:flex;align-items:center;gap:13px;padding:11px 2px}
.hair{height:1px;background:var(--hair)}
.tile{width:52px;height:52px;flex:0 0 52px;background:var(--surface);border:2px solid;border-radius:13px;display:flex;align-items:center;justify-content:center;overflow:hidden}
.glyph{width:100%;height:100%;color:var(--ink);display:flex;align-items:center;justify-content:center}
.glyph svg{width:100%;height:100%;display:block}
.tile .glyph{padding:5px}
.rowtext{flex:1;min-width:0}
.rowname{font-size:17px;line-height:1.15;color:var(--ink)}
.rowsub{font-family:'Space Grotesk',ui-sans-serif,system-ui,sans-serif;font-size:12.5px;color:var(--ink3);margin-top:3px}
.chev{color:var(--ink3);font-size:22px;font-family:ui-sans-serif,system-ui}
.detail{margin-top:8px;background:var(--surface);border:1px solid var(--hairS);border-radius:18px;padding:18px}
.detail h2{font-size:24px;font-weight:400;letter-spacing:-.01em}
.detail .sub{font-family:'Space Grotesk',ui-sans-serif,system-ui,sans-serif;font-size:12.5px;color:var(--ink3);margin-top:4px;text-transform:uppercase;letter-spacing:.08em}
.herobig{width:150px;height:150px;margin:14px auto 4px;color:${hero.fam}}
.herobig .glyph{color:var(--ink)}
.strip{display:flex;gap:10px;justify-content:center;margin-top:12px}
.frame{flex:1;background:var(--paper);border:1px solid var(--hair);border-radius:12px;padding:8px}
.frame .glyph{height:74px;color:var(--ink)}
.framelbl{font-family:'Space Grotesk',ui-sans-serif,system-ui,sans-serif;font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:var(--ink3);text-align:center;margin-top:6px}
.note{max-width:390px;margin:0 auto;background:var(--surface);border:1px solid var(--hairS);border-left:3px solid ${EMBER};border-radius:12px;padding:15px 16px;font-size:13.5px;line-height:1.5;color:var(--ink2)}
.note b{color:var(--ink)}
.note h3{font-family:'Space Grotesk',ui-sans-serif,system-ui,sans-serif;font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--ink3);margin-bottom:8px}
.note ul{margin:8px 0 0 18px}
.note li{margin-bottom:5px}
.cap{max-width:390px;margin:20px auto 6px;font-family:ui-sans-serif,system-ui;font-size:11px;color:#94897a;text-align:center}
</style></head><body>

<div class="phone">
  <div class="kicker">Biblioteca · 873 ejercicios</div>
  <div class="search"><span class="grotesk" style="font-weight:700">⌕</span> Buscar ejercicio</div>

  <div class="band"><span>Empuje · De la biblioteca</span></div>
  ${rowHTML}

  <div class="detail">
    <div class="sub">Detalle · propuesta</div>
    <h2>${hero.name}</h2>
    <div class="sub" style="text-transform:none;letter-spacing:0;margin-top:2px">${hero.sub}</div>
    <div class="herobig"><div class="glyph">${heroFrames[2]||""}</div></div>
    <div class="strip">${heroStrip}</div>
  </div>
</div>

<div class="note">
  <h3>Qué estás viendo (spike)</h3>
  Siluetas reales del set abierto <b>@bryllim/workout-guide</b> (base <b>Everkinetic</b>), recoloreadas a la tinta <b>#221D16</b> sobre papel <b>#F4F1E8</b>, en el layout real de la fila de la Biblioteca. El borde de 2 px lleva la <b>familia de movimiento</b> (empuje·ámbar / jalón·teal / pierna·índigo); la silueta es monocroma.
  <ul>
    <li><b>Cobertura si solo adoptamos:</b> ~100–150 de nuestros 873 (~12–17%), en los levantamientos comunes. El long tail (cardio, máquinas, estiramientos) no recibe nada.</li>
    <li><b>Licencia del arte:</b> CC BY-SA 4.0 → atribución + <i>share-alike</i> en lo que modifiquemos.</li>
    <li><b>Estilo:</b> son <i>siluetas rellenas</i> (potrace), no trazo de una línea. ¿Lee como «Instrumento diurno» o se siente ajeno?</li>
  </ul>
</div>
<div class="cap">Spike interno de evaluación · arte © Everkinetic / Bryl Lim, CC BY-SA 4.0</div>

</body></html>`;

writeFileSync("/tmp/claude-0/-home-user-noop/adcbf89a-72e6-5747-b095-c4f2a67b7fe9/scratchpad/cenit-siluetas-spike.html", html);
console.log("wrote preview,", html.length, "bytes; rows with svg:", rows.filter(r=>r.svg).length, "hero frames:", heroFrames.filter(Boolean).length);
