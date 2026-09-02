# Sellos de Hoy — el forjador

Los diez glifos de métrica de la pantalla **Hoy**, generados por computación en vez de dibujados a
mano: `forge.py` construye cada silueta como unión de discos sobre un esqueleto (bézier, arco o
polilínea) con radio variable, la mide, la normaliza y la emite como paths SVG.

> **Estado: diseño, no producción.** Todavía no hay issue de Multica ni implementación en Swift.
> Esto se preserva aquí porque es la fuente de la geometría que `/implement` necesitará, y porque
> el specimen es lo que el dueño aprueba antes de codear.

## Uso

```bash
cd Tools/sellos-hoy && python3 forge.py     # requiere shapely + numpy
```

Emite `glyphs.json` (el payload) y lo inyecta en `specimen.html` — **fuente única**: no edites el
payload del HTML a mano, se pierde en el siguiente forjado. El script imprime su propia auditoría:
tamaño y masa de tinta por glifo, simetría de espejo, área segura, separación mínima a 20 pt, y
solapes entre partes de color distinto.

## Lo que el generador garantiza

- **Los huecos declarados existen.** `arc_ink()` retrae el esqueleto por la extensión angular del
  remate redondo (`asin(r/R)`). Sin eso, todo hueco menor que esa extensión se cierra solo, los
  arcos se solapan y el orden de pintado sesga el reparto de color.
- **Nada sub-pixel al tamaño real.** El sello más chico de la Matriz mide 20 pt: el piso de remate
  es 0.75 u (≈1.25 px) y la verificación falla ruidosamente si una separación estructural baja de ahí.
- **Normalización óptica, no de bounding box.** Se iguala la extensión, pero una masa ya pesada
  nunca se agranda — igualar bbox a secas le daba el upscale máximo justo a las siluetas sólidas.
- **Simetría verificada con número.** Diferencia de espejo sobre el eje x=12, no a ojo. Los glifos
  con asimetría intencional (creciente, onda, cometa, zancada) están declarados como tales.

## Contrato de color

Cada sello viste el token que `Instrumento.swift` le asigna a **su** métrica. Antes del handoff
faltan por acuñar en `CenitDesign`:

| Pendiente | Valor | Para |
|---|---|---|
| `azulHondo` | `#2A5480` | lectura de respiración · mitad de la esfera del guardián |
| `tealHondo` | `#35707E` | cabeza del caminante |
| regla del stop claro | HSL `L + 0.075` sobre el tono base | el degradado vertical de todo el cuerpo |

Dos conflictos del SSOT quedan abiertos para `/pm`, no se resolvieron aquí:

1. `MetricGlyph.swift` manda `skinTemp → dataStrain` (`#C4631F`), pero `LiquidColor.swift` documenta
   `doradoTemp` (`#8A6A2B`) como identidad exclusiva de temperatura de piel. El sello usa el dorado.
2. `strain`, `skinTemp` y `trainingLoad` comparten `dataStrain`. Una familia de diez sellos necesita
   distinguirlos: aquí lo hace la **forma** (cometa · termómetro · pesa), y carga toma `dataOxygen`
   para no vestir la voz de marca verde. Si se quiere identidad cromática propia, hay que acuñar un
   token de dato para carga.
