# Auditoría B1 — Pieza equivocada y evasiones (MITAD 1)

> **Solo reporte.** Cero cambios a Swift/CI/linter/baselines.  
> **Issue:** FER-279 · **rama:** `grok/fer-279b1-uso-1788282399-76192-27724`  
> **Fecha:** 2026-09-01 · **ejes:** 1 (pieza equivocada) y 2 (evasiones fuera de gate).  
> **Árbol auditado:** `Cenit/**`, `CenitWidgets`, `CenitWatch`, `Packages/StrandDesign/Sources`.

## Método (qué se leyó)

| Insumo | Uso |
|---|---|
| `docs/design-system/CATALOGO.md` | Índice rol→símbolo→«cuándo no» (líneas 118–140) |
| `docs/design-system/CONTRATO.md` | Matriz de 15 gates + indecidibles (§ «Alta estructural» / FER-276) |
| `docs/design-system/CENSO.md` + `CENSO.json` | Colador de evasiones §1; TOP archivos; commit `8f08a6342cf0` |
| `Tools/check-design-drift.py` | Las 15 reglas y qué regex **no** ven (`.frame`, `.offset`, `Color.clear`, `.safeAreaPadding`) |
| `Tools/design-drift-baseline.json` | Deuda congelada (contexto; no se reescribe) |
| `docs/design-system/AUDITORIA-SISTEMA.md` | Cruce con Auditoría C (paquete por dentro — solo referencia) |

Barridos: `rg` sobre call-sites de cada pieza del catálogo + patrones de evasión nuevos (`.fill(….opacity)`, `frame(minHeight:)`, `blur(`, `LinearGradient`, overlays de borde a mano). Spot-checks con lectura de contexto en archivo:línea.

**WIP:** hallazgos se van añadiendo por eje; veredicto global al cierre.

---

## Eje 1 · Pieza equivocada

_Pendiente de relleno — en curso._

---

## Eje 2 · Evasiones vivas fuera de gate

_Pendiente de relleno — en curso._

---

## Veredicto global

_Pendiente._
