---
name: implement
description: >-
  Lleva un issue de Linear (ya especificado por /pm) de requerimiento hasta
  producción, solo. Lo mueve a In Progress, crea su rama limpia desde iOS,
  implementa contra los criterios de aceptación, verifica cada uno (QA real:
  build + tests) y, si todo pasa, abre el PR, lo mergea a iOS, cierra el issue
  en Done y borra la rama. Se detiene a preguntarte solo si el QA falla, no puede
  verificar, o el cambio es riesgoso. Es la etapa de código + QA + entrega del
  flujo, después de /pm. Dispáralo con /implement FER-NN.
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
7. **QA — verifica cada criterio (el gate).**
   - Compila y corre los tests del área tocada (comandos en `CLAUDE.md`).
   - Recorre los criterios de aceptación y el Definition of Done **uno por uno**.
   - Si hubo pasada de UI: verifica los **criterios de UI** (solo tokens
     StrandDesign, sin hex/spacing inline) y que **el render real coincida con el
     PNG aprobado**.
   - Si algo falla, corrígelo. Si no puedes corregirlo o no puedes verificar, ve a
     "Cuándo PARAR".
8. **Entrega (solo si TODO el QA pasó).** Commit descriptivo + **entrada en la
   bitácora de producto** (`CHANGELOG.md` — obligatoria si el cambio es visible
   para el usuario; ver "La bitácora de producto" abajo) → push → PR hacia `iOS`
   (`Closes FER-NN`, criterios verificados en "How it was tested") →
   **squash-merge a `iOS`** → **borra la rama** (`--delete-branch`).
9. **Actualiza el checkout de build.** Tras el merge, sincroniza el checkout
   canónico (`~/code/noop`, de donde sale el build del iPhone) para que el próximo
   build NO sea viejo: `git -C ~/code/noop fetch origin` y luego
   `git -C ~/code/noop merge --ff-only origin/iOS`. Usa `--ff-only`: preserva
   cualquier trabajo sin commitear que haya ahí y NUNCA lo pisa. Si falla (el
   checkout tiene cambios que chocan o divergió), NO fuerces: avísale al usuario en
   lenguaje claro que actualice su checkout antes de compilar.
10. **Cierra y limpia.** Mueve el issue a `Done` con un comentario y el link del PR.
    Deja el worktree limpio (de vuelta en `iOS` actualizado, sin ramas colgando).
11. **Reporta en lenguaje claro** (el usuario NO es técnico): qué cambió en la app,
    qué criterios quedaron verificados, y que ya está en `iOS` **y en su checkout
    principal**. El único paso manual que le queda: abrir Xcode y compilar/instalar
    en su iPhone.

## La bitácora de producto (`CHANGELOG.md`) — qué cambió, en cristiano

`CHANGELOG.md` (en la raíz) es la bitácora que **el usuario lee para entender cómo
evoluciona la app**, sin jerga. **No es opcional:** todo cambio que el usuario
pueda ver o usar —una pantalla, una métrica, un copy, un comportamiento, un fix
visible— **agrega una entrada bajo `## Unreleased` antes de mergear** (paso 8). Los
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
- No mergees si el QA no pasó o si es de alto riesgo (ver "Cuándo PARAR").
- No repitas ni contradigas `CLAUDE.md` / `docs/CONTRIBUTING.md`; síguelos.
