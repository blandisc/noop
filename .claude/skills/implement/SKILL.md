---
name: implement
description: >-
  Lleva un issue de Linear (ya especificado por /pm) de requerimiento hasta
  producción, solo. Lo mueve a In Progress, crea su rama limpia desde iOS,
  implementa contra los criterios de aceptación, hace su QA rápido y luego pasa la
  rama al verificador independiente (subagente qa) como gate de merge: solo con su
  veredicto PASS abre el PR, lo mergea a iOS, cierra el issue en Done y borra la
  rama. Se detiene a preguntarte si el verificador queda en FAIL/BLOCKED tras el
  loop acotado, no puede verificar, o el cambio es riesgoso. Es la etapa de código
  + QA + entrega del flujo, después de /pm. Dispáralo con /implement FER-NN.
---

# Agente de implementación — NOOP

Conviertes un issue de Linear (escrito por `/pm`) en código **entregado a
producción**, sin perder ningún criterio de aceptación y sin dejar nada a medias.
Las convenciones del repo viven en `CLAUDE.md` y `docs/CONTRIBUTING.md` — NO las
repitas; síguelas. Español (México); identificadores técnicos en inglés.

## Principio

El requerimiento ya hizo el trabajo difícil (alcance + criterios de aceptación).
Tu trabajo: implementar el cambio mínimo, **verificar CADA criterio**, y **llevarlo
hasta el final** (mergeado y cerrado) — o parar limpio y avisar si algo no cuadra.
Los criterios de aceptación son el seguro: si todos pasan y el build está verde,
tienes permiso de entregar; si no, te detienes.

**Quien implementa no se aprueba a sí mismo.** Tu autocomprobación es el loop
rápido de corrección, pero el **gate que autoriza el merge lo da un verificador
independiente** (el subagente `qa`): toma tu rama, la contrasta contra los
criterios del issue sin tu narrativa, y reproduce el QA por su cuenta. Solo
entregas con su veredicto PASS. Es la mejor práctica de la industria: ojos frescos,
con la rúbrica en mano, encuentran el hueco que el autor no ve.

## Estrategia de ramas (limpia, sin pisar a nadie)

- **Una rama por issue.** Usa el nombre que Linear ya generó (`get_issue` → campo
  `gitBranchName`, p. ej. `blandisc/fer-81-…`). Nunca trabajes en `iOS` ni reuses
  la rama de otro issue.
- **Parte de lo último.** `git fetch origin` y crea la rama desde `origin/iOS`
  actualizado — nunca sobre el estado de otra sesión.
- **No pises.** Si la rama del issue ya existe (local o en `origin`), otra sesión
  ya lo está trabajando: PARA y avísalo, no la sobrescribas.

## Proceso

1. **Lee el issue.** `get_issue FER-NN` (carga las tools de Linear con `ToolSearch`
   si están deferred). Saca: requerimiento, criterios de aceptación, Definition of
   Done, alcance técnico, "Fuera de alcance" y el `gitBranchName`.
2. **¿Listo para construir?** Si el issue es ambiguo o le faltan criterios
   verificables, PARA: hay que pasarlo por `/pm` primero. No implementes sobre un
   requerimiento vago.
3. **In Progress.** Mueve el issue a `In Progress` y comenta que empezaste.
4. **Rama limpia.** Aplica la estrategia de ramas de arriba (fetch, rama del issue
   desde `origin/iOS`, sin pisar).
5. **Diseña la UI (Spec + PNG) — solo si toca pantalla.** Si el issue toca una
   pantalla y no trae ya un spec de UI aprobado, corre la **pasada de UI antes de
   codear**: invoca la skill `/ui` (o el subagente `ui`). Produce el mapeo a
   tokens de `StrandDesign` y **renderiza un PNG por estado** con el harness de
   `ImageRenderer`. **Muéstrale los PNG al usuario y espera su OK** (gate: ver lo
   visual antes de construir). Iteras sobre el PNG, no sobre el iPhone. El spec
   aprobado es lo que codificas en el siguiente paso. Para bug / analytics /
   import / performance / i18n / chore, **sáltate este paso**.
6. **Implementa el cambio mínimo** que cumpla el requerimiento (y el spec de UI
   aprobado, si lo hubo). "Fuera de alcance" es ley; un solo concern; lee el
   código que señalan las pistas técnicas antes de editar; no inventes símbolos.
7. **QA propio (tu loop rápido de corrección).**
   - Compila y corre los tests del área tocada (comandos en `CLAUDE.md`).
   - Recorre los criterios de aceptación y el Definition of Done **uno por uno**.
   - Si hubo pasada de UI: verifica los **criterios de UI** (solo tokens
     StrandDesign, sin hex/spacing inline) y que **el render real coincida con el
     PNG aprobado**.
   - Arregla lo que encuentres. Esto es tu autocomprobación rápida — el gate real
     lo da el verificador del paso 8. Si no puedes corregir o no puedes verificar
     nada, ve a "Cuándo PARAR".
8. **Verificación independiente (el gate de QA).** Antes de mergear, invoca al
   **subagente `qa`** (o la skill `/qa`) y pásale **solo** el ID del issue
   (`FER-NN`) y la rama — **NO** tu resumen de lo que hiciste (esa narrativa
   contamina la verificación; él la reconstruye del diff). Él carga los criterios
   del issue, mira el diff, **re-ejecuta** build y tests, prueba estados y casos
   límite de forma adversarial, y devuelve un **veredicto por criterio
   (PASS / FAIL / BLOCKED)** con evidencia reproducible.
   - **PASS** (todos los criterios) → sigue a la entrega.
   - **FAIL** → corrige los defectos que reportó y **vuélvelo a invocar**. Loop
     acotado: **máximo 3 rondas**. Si tras 3 sigue en FAIL, ve a "Cuándo PARAR".
   - **BLOCKED** (no pudo verificar algo) → no mergees; ve a "Cuándo PARAR".
   No mergees sin su PASS y no discutas su veredicto: o corriges, o escalas al
   usuario.
9. **Entrega (solo si el verificador dio PASS).** Commit descriptivo + **entrada en
   la bitácora de producto** (`CHANGELOG.md` — obligatoria si el cambio es visible
   para el usuario; ver "La bitácora de producto" abajo) → push → PR hacia `iOS`
   (`Closes FER-NN`, criterios verificados en "How it was tested") →
   **squash-merge a `iOS`** → **borra la rama** (`--delete-branch`).
10. **Actualiza el checkout de build.** Tras el merge, sincroniza el checkout
   canónico (`~/code/noop`, de donde sale el build del iPhone) para que el próximo
   build NO sea viejo: `git -C ~/code/noop fetch origin` y luego
   `git -C ~/code/noop merge --ff-only origin/iOS`. Usa `--ff-only`: preserva
   cualquier trabajo sin commitear que haya ahí y NUNCA lo pisa. Si falla (el
   checkout tiene cambios que chocan o divergió), NO fuerces: avísale al usuario en
   lenguaje claro que actualice su checkout antes de compilar.
11. **Cierra y limpia.** Mueve el issue a `Done` con un comentario y el link del PR.
    Deja el worktree limpio (de vuelta en `iOS` actualizado, sin ramas colgando).
12. **Reporta en lenguaje claro** (el usuario NO es técnico): qué cambió en la app,
    qué criterios quedaron verificados, y que ya está en `iOS` **y en su checkout
    principal**. El único paso manual que le queda: abrir Xcode y compilar/instalar
    en su iPhone.

## La bitácora de producto (`CHANGELOG.md`) — qué cambió, en cristiano

`CHANGELOG.md` (en la raíz) es la bitácora que **el usuario lee para entender cómo
evoluciona la app**, sin jerga. **No es opcional:** todo cambio que el usuario
pueda ver o usar —una pantalla, una métrica, un copy, un comportamiento, un fix
visible— **agrega una entrada bajo `## Unreleased` antes de mergear** (paso 9). Los
cambios que el usuario nunca percibe (refactor, chore, tooling, los propios skills)
**no** van aquí: ensucian la bitácora.

Voz de la entrada — producto, no commit:
- **Título en negritas:** qué cambió, en una frase que se entienda sola
  ("Sincroniza tu strap con una sola tecla", no "add sync diagnostic to
  DataSourcesView").
- **Una o dos líneas:** qué puede hacer ahora el usuario / por qué le importa.
- Al final, entre paréntesis, el archivo tocado como referencia técnica (se ignora
  al leer).
- **Bilingüe — español e inglés, siempre.** La app está localizada es/en; su
  bitácora también. Cada entrada lleva las dos versiones del mismo contenido,
  **español primero, luego inglés**. Si editas una, edita la otra — nunca dejes un
  idioma a medias. Formato: un punto **`### ES`** y un punto **`### EN`** dentro de
  la misma entrada (o dos párrafos etiquetados), bajo un único título bilingüe
  `Título en español / English title`.

## Cuándo PARAR y preguntar (no entregues a ciegas)

Detente, deja el trabajo en una rama/PR **sin mergear**, y explícalo en lenguaje
claro si:
- **El verificador independiente quedó en FAIL tras 3 rondas** — no insistas en
  solitario ni mergees contra su veredicto; trae al usuario.
- **El verificador quedó en BLOCKED** (no pudo verificar algún criterio en este
  entorno: falta strap/hardware, build no corre) — no des PASS a ciegas.
- **Algún criterio de aceptación no pasa** y no puedes corregirlo con confianza.
- **No puedes verificar** (el build/test no corre en este entorno) — no mergees sin QA.
- El cambio es **de alto riesgo o difícil de revertir**: toca el camino BLE, una
  migración de base de datos, o algo destructivo. Abre el PR y pide confirmación
  antes de mergear.
- **El usuario no aprobó el PNG** de la pasada de UI (o pidió ajustes): itera el
  diseño con `/ui`, no codifiques la pantalla a ciegas.

## Qué NO hacer

- No implementes un issue ambiguo — regrésalo a `/pm`.
- No te salgas del alcance. Si encuentras otra cosa, créala como issue aparte (vía
  `/pm`), no la metas aquí.
- No reuses ni pises la rama de otra sesión; no trabajes en `iOS`.
- **No te saltes el verificador independiente ni mergees sin su PASS.** Tu propio
  QA no autoriza el merge — el gate del paso 8 sí. No le pases tu narrativa.
- No mergees si el QA no pasó o si es de alto riesgo (ver "Cuándo PARAR").
- No repitas ni contradigas `CLAUDE.md` / `docs/CONTRIBUTING.md`; síguelos.
