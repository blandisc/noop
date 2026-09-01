# CONTRATO.md — el contrato del sistema de diseño ejecutable

> **Escrito a mano** (FER-265, épico FER-261). Este archivo es proceso, no tokens: DESIGN.md tiene
> bloques que `StrandDesignTokens` regenera y por eso el contrato NO puede vivir ahí. La matriz de
> gates de abajo la valida `Tools/check-gate-parity.py` en CI — si editas una pata sin editar la
> matriz (o al revés), `design-lint` falla.

## Qué es qué

- **Token**: un valor de diseño con nombre en `Packages/StrandDesign` (`LiquidColor`, `LiquidSpace`,
  `LiquidRadius`, `CenitMetrics`, `StrandOpacity`…). La escala `LiquidSpace` (nombrada por valor:
  `s400 = 16`) es el DNA canónico y **se queda**; los roles semánticos (`LiquidRadius.tarjeta`) se
  usan donde ya existen y para tokens nuevos. El diccionario vivo está en
  [CATALOGO.md](CATALOGO.md) (generado — el código gana).
- **Componente**: una pieza que consume tokens (`liquidGlass(_:)`, `StatTile`, …) y encapsula una
  decisión completa. *Una pantalla se compone, no se dibuja.*
- **Deuda**: un literal de diseño, un call-site de API legacy, o una exención — todo congelado en
  `Tools/design-drift-baseline.json` con trinquete: **ningún conteo puede subir** (job
  `baseline-monotony`), y bajar solo cuenta si es real (valor tokenizado o pieza usada).

## Cómo se pide un token/componente nuevo (tope de vocabulario)

1. Verifica en [CATALOGO.md](CATALOGO.md) que no exista ya — reimplementar lo existente es la clase
   de defecto más cara medida en este repo (FER-119: 15 defectos).
2. La pieza nueva nace en `StrandDesign` con `#Preview`, nombrada por rol, y se anota en el reporte
   del censo ([CENSO.md](CENSO.md)). Aplica a **cualquier** primitivo (también pasos de escala y
   constantes de `LiquidLayout`). Prohibido mintear roles basura para esquivar `token ± n`
   (`space1plus2 = 6` no es un rol).
3. Durante la Fase 1 del épico FER-261, el vocabulario completo lo aprueba **el dueño una sola vez**
   con preview visual (FER-268). Después de esa sesión: PR normal, sin ceremonia extra — vigilan el
   tope y el trinquete de exenciones.

## Cómo se anota una excepción

- Forma nueva (obligatoria): `// token-exempt(<categoria>): <motivo>` con `<categoria>` ∈
  `dato` (geometría de datos: barras, legends, keypad) · `sistema` (Dynamic Island / watch face) ·
  `falta-pieza` (no hay token exacto — **candidata a pieza**, la audita la regla ×3) ·
  `optico` (ajuste óptico deliberado) · `paridad` (espejo de un valor privado) · `unico` (rareza
  genuina). Las 248 anotaciones legacy sin categoría están congeladas, no se reescriben.
- **Una exención nueva es deuda**: la pseudo-regla `token-exempt` la cuenta y el trinquete la
  rechaza sin alta legal. `padding(0)` y la geometría de datos no son deuda conceptual, pero pagan
  la misma anotación para que el censo las clasifique.
- **Regla ×3**: si el mismo patrón junta 3 exenciones `falta-pieza`, no son 3 excepciones — es un
  componente que falta. El censo lo reporta como cluster con pieza propuesta.

## Alta legal del baseline (la ÚNICA)

El job `baseline-monotony` falla ante cualquier conteo que suba respecto a la base del PR. El
bypass exige **dos condiciones verificadas por el script** (jamás «el JSON viene en el PR»):

1. Label **`baseline-alta`** — la aplica **solo el dueño**, sobre un PR que implementa un issue FER
   dedicado al alta.
2. El PR es **solo-baseline**: su diff toca únicamente `Tools/design-drift-baseline.json` y/o
   `docs/**`. Un solo `.swift`/`.yml`/`Tools/*.py` en el diff anula el bypass, label o no.

Local: `verify.sh` espeja la monotonía contra `origin/iOS`; el PR de alta corre con
`CENIT_BASELINE_ALTA=1` (más laxo que CI a propósito: local es espejo, **CI es la autoridad**).
El hook pre-commit se queda delgado: sin monotonía ni paridad.

**Rename con deuda** (caso conocido): renombrar un archivo con presupuesto exige el baile de dos
PRs — primero el alta legal de la clave nueva (issue dedicado), luego el rename — o pagar la deuda
antes. No hay atajo en un solo PR, por diseño.

**Ajustes del repo que esto asume** (los aplica el dueño en GitHub, no son archivos):
`baseline-monotony` como *required check* de `iOS`, y la label `baseline-alta` restringida.

## Carve-outs (dónde los gates NO aplican, por decisión)

- **CenitWidgets / CenitWatch**: fuera de `no-legacy-api` y `token-exempt` (y del spacing hasta que
  cierre FER-219) — geometría fija de Dynamic Island / watch face; `InstrumentoTheme` es el tema
  **canónico** de la Live Activity. El carve-out vive en `check()` del linter, no solo en la
  invocación.
- **CenitShared**: no importa `StrandDesign` a propósito (frontera de paquetes: Codable no puede
  depender del paquete de UI) — no hay nada que gatear ahí.
- **Watch OLED**: la excepción viva del sistema oscuro; es su propio contexto de arbitraje, no
  deuda.

## Checklist Fase 1 — wrapping valor-neutral (cero pixel)

Todo issue de lote de wrapping **copia estos 5 puntos como criterios de aceptación**:

1. **Igualdad exacta**: el token elegido vale exactamente el literal que envuelve (`14` jamás se
   envuelve en `s400 = 16`). Sin token exacto → el sitio va a la lista de `/migracion`, no se
   envuelve.
2. **Check mecánico del diff**: `git diff -U0 | grep -E '^[+-].*[0-9]'` — cada línea `-` con número
   tiene su `+` con símbolo; ningún cambio dígito→dígito.
3. La descripción del PR lista cada par `literal → token`.
4. **Test de valor en el mismo PR**: `DesignDriftTokenTests` asevera `token == literal envuelto`.
5. `/qa` re-corre el punto 2 sobre el diff completo — check literal, no narrativa.

## Regla de arbitraje de colisiones

Cuando N valores compiten por el mismo rol: gana **Liquid Glass · El Eje**, en su contexto — hay
**tres**: mosaico, sobrio y **Watch OLED** (el Watch no se pinta de blanco). Si Liquid no define el
rol, gana el valor más frecuente entre pantallas ya migradas; empate → decide el dueño con preview.
Los veredictos viven en [CENSO.md](CENSO.md); a `docs/DECISIONS.md` solo sube la política.
**Aplicar** un veredicto (cambiar píxeles) es trabajo de los lotes trimestrales (`/migracion` para
pantalla entera; polish en `/canvas` para lote transversal de un rol, N ≤ 10) — nunca de tooling.

## Caducidad del censo

`CENSO.md` lleva el commit en que se generó. Se re-corre **antes de cada lote trimestral** y antes
de la sesión del dueño; un censo de más de un trimestre no sirve para arbitrar.

## Matriz de gates

Tabla humana (resumen) — la verdad máquina-legible es el bloque JSON de abajo, que
`Tools/check-gate-parity.py` contrasta contra `verify.sh`, el hook y `design-lint.yml`:

| Regla | pre-commit | verify quick | design-lint (CI) |
|---|---|---|---|
| no-hex | staged (todos) | changed (todos) | árbol (raíces default) |
| no-adhoc-font / no-radius-literal / no-opacity-literal | staged Screens+Onboarding | changed Screens+Onboarding | árbol Screens+Onboarding |
| no-emdash-string | staged Screens+Onboarding | changed Screens+Onboarding | árbol Screens+Onboarding |
| no-raw-shadow | staged Screens | changed Screens | árbol Screens |
| no-sheet-glass | staged (todos)¹ | changed (todos)¹ | árbol StrandDesign+Cenit+CenitApp+CenitShared+CenitWidgets |
| no-spacing-literal (trinquete) | árbol 4 raíces | árbol 4 raíces | árbol 4 raíces |
| no-legacy-api (trinquete) | árbol 7 raíces | árbol 7 raíces | árbol 7 raíces |
| token-exempt (trinquete) | árbol 7 raíces + StrandDesign | árbol 7 raíces + StrandDesign | árbol 7 raíces + StrandDesign |
| monotonía del baseline | — (hook delgado) | espejo vs origin/iOS | job `baseline-monotony` |

¹ divergencia declarada: local corre sobre los archivos tocados (más estricto en Watch); CI usa las
raíces explícitas donde vive el defecto (incluye el paquete, excluye CenitWatch).

<!-- gate-matrix:begin -->
```json
{
  "baseline_path": "Tools/design-drift-baseline.json",
  "tree_roots": {
    "spacing": ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App"],
    "legacy": ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App", "Cenit/Data", "Cenit/LiveActivity", "Cenit/Media"],
    "exempt": ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App", "Cenit/Data", "Cenit/LiveActivity", "Cenit/Media", "Packages/StrandDesign/Sources"],
    "sheet_glass_ci": ["Packages/StrandDesign/Sources", "Cenit", "CenitApp", "CenitShared", "CenitWidgets"]
  },
  "rules": {
    "no-hex":             {"pre-commit": "staged", "verify-quick": "changed", "design-lint": "tree-default"},
    "no-adhoc-font":      {"pre-commit": "staged-screens-onboarding", "verify-quick": "changed-screens-onboarding", "design-lint": "tree:Cenit/Screens Cenit/Onboarding"},
    "no-radius-literal":  {"pre-commit": "staged-screens-onboarding", "verify-quick": "changed-screens-onboarding", "design-lint": "tree:Cenit/Screens Cenit/Onboarding"},
    "no-opacity-literal": {"pre-commit": "staged-screens-onboarding", "verify-quick": "changed-screens-onboarding", "design-lint": "tree:Cenit/Screens Cenit/Onboarding"},
    "no-emdash-string":   {"pre-commit": "staged-screens-onboarding", "verify-quick": "changed-screens-onboarding", "design-lint": "tree:Cenit/Screens Cenit/Onboarding"},
    "no-raw-shadow":      {"pre-commit": "staged-screens", "verify-quick": "changed-screens", "design-lint": "tree:Cenit/Screens"},
    "no-sheet-glass":     {"pre-commit": "staged", "verify-quick": "changed", "design-lint": "tree:sheet_glass_ci", "nota": "raices distintas a proposito: el defecto vive en el paquete; local mas estricto"},
    "no-spacing-literal": {"pre-commit": "tree:spacing+baseline", "verify-quick": "tree:spacing+baseline", "design-lint": "tree:spacing+baseline"},
    "no-legacy-api":      {"pre-commit": "tree:legacy+baseline", "verify-quick": "tree:legacy+baseline", "design-lint": "tree:legacy+baseline"},
    "token-exempt":       {"pre-commit": "tree:exempt+baseline", "verify-quick": "tree:exempt+baseline", "design-lint": "tree:exempt+baseline"}
  }
}
```
<!-- gate-matrix:end -->
