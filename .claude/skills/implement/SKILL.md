---
name: implement
description: >-
  Lleva un issue de Multica (ya especificado por /pm) de requerimiento hasta
  producción, solo. Lo mueve a in_progress, crea su rama limpia desde iOS,
  implementa contra los criterios de aceptación, hace su QA rápido y luego pasa la
  rama al verificador independiente (subagente qa) como gate de merge: solo con su
  veredicto PASS abre el PR, lo mergea a iOS, cierra el issue en done y borra la
  rama. Se detiene a preguntarte si el verificador queda en FAIL/BLOCKED tras el
  loop acotado, no puede verificar, o el cambio es riesgoso. Es la etapa de código
  + QA + entrega del flujo, después de /pm. Dispáralo con /implement FER-NN.
---

# Agente de implementación — NOOP

Conviertes un issue de Multica (escrito por `/pm`) en código **entregado a
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

**Pero el gate independiente solo corre en el carril pesado.** No todo merece el
mismo QA: ver "Carril" abajo.

## Carril (cuánto QA corre depende del riesgo)

Lee el campo **`Carril`** del issue (lo fija `/pm`). Si el issue no lo trae,
derívalo: **pesado** si toca BLE/protocolo, una migración de DB, analítica/math,
datos on-device difíciles de revertir, algo cross-paquete / concurrencia, o una
feature con lógica real; **ligero** si es UI / copy / layout / i18n reversible.
**En la duda, pesado** — y si lo marcaron ligero pero al codear ves que roza un
disparador pesado, súbelo a pesado.

- **Pesado:** el proceso completo de abajo, **incluido el verificador independiente
  `/qa` (paso 8) y la pasada de `/simplify` (paso 8.5)**.
- **Ligero:** implementas, corres tu propio build + verificas los criterios uno por
  uno, apruebas lo visual con **preview HTML** si toca pantalla, y entregas —
  **sin** el subagente `/qa`, sin el loop de 3 rondas, sin `/arquitecto`. Tu propio
  QA + el preview es suficiente; el usuario lo confirma en su iPhone y rehacer un
  cambio cosmético cuesta segundos.

## Estrategia de ramas (limpia, sin pisar a nadie)

- **Una rama por issue.** Nombre desde el identifier Multica + slug corto
  (`fer-81-empty-today-state`). Nunca trabajes en `iOS` ni reuses la rama de otro
  issue.
- **Parte de lo último.** `git fetch origin` y crea la rama desde `origin/iOS`
  actualizado — nunca sobre el estado de otra sesión.
- **No pises.** Si la rama del issue ya existe (local o en `origin`), otra sesión
  ya lo está trabajando: PARA y avísalo, no la sobrescribas.

## Proceso

1. **Lee el issue.** `multica issue get FER-NN --output json`. Saca: requerimiento,
   criterios de aceptación, Definition of Done, alcance técnico y "Fuera de alcance".
   Rama: `fer-NN-<slug-corto>` (no hay `gitBranchName` de Linear).
2. **¿Listo para construir?** Si el issue es ambiguo o le faltan criterios
   verificables, PARA: hay que pasarlo por `/pm` primero. No implementes sobre un
   requerimiento vago.
3. **in_progress.** `multica issue status FER-NN in_progress` y comenta con
   `multica issue comment add <id> --content "…"` que empezaste.
4. **Rama limpia.** Aplica la estrategia de ramas de arriba (fetch, rama del issue
   desde `origin/iOS`, sin pisar).
5. **Diseña la UI — solo si toca pantalla.** Si el issue toca una pantalla y no
   trae ya un spec de UI aprobado, invoca `/ui` (o el subagente `ui`) antes de
   codear. El gate de aprobación (preview HTML + OK del usuario) lo maneja `/ui`
   internamente — no lo repitas aquí. El spec aprobado que devuelva es lo que
   codificas en el siguiente paso. Para bug / analytics / import / performance /
   i18n / chore, **sáltate este paso**.
6. **Implementa el cambio mínimo** que cumpla el requerimiento (y el spec de UI
   aprobado, si lo hubo). "Fuera de alcance" es ley; un solo concern; lee el
   código que señalan las pistas técnicas antes de editar; no inventes símbolos.
7. **QA propio (tu loop rápido de corrección).**
   - Compila y corre los tests del área tocada (comandos en `CLAUDE.md`). Para
     tests de la **app** (capa `Cenit/`), `-destination 'generic/platform=iOS'`
     solo compila; para correrlos headless usa
     `xcodebuild test-without-building -destination 'id=<simulador concreto>'`
     (técnica de FER-149; `xcrun simctl list devices available` da un id).
   - Recorre los criterios de aceptación y el Definition of Done **uno por uno**.
   - Si hubo pasada de UI: verifica los **criterios de UI** (solo tokens
     CenitDesign, sin hex/spacing inline) y que **el render real coincida con el
     preview aprobado**.
   - Arregla lo que encuentres. En **carril ligero** esto es tu verificación final;
     en **carril pesado** es solo tu loop rápido — el gate real lo da el verificador
     del paso 8. Si no puedes corregir o no puedes verificar nada, ve a "Cuándo
     PARAR".
8. **Verificación independiente (el gate de QA) — solo carril pesado.** Antes de
   mergear, invoca al
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
8.5 **Simplifica (solo carril pesado, tras el PASS).** Corre la skill `/simplify`
   sobre tu diff: los agentes tienden a sobre-construir (abstracciones de un solo
   uso, duplicación, código de más). Aplica lo que recorte **sin cambiar el
   comportamiento ya verificado**; si toca algo de fondo, vuelve a pasar el `/qa`.
   No es cacería de bugs (eso fue el paso 8) — es dejar el mínimo que cumple.
9. **Entrega (ligero: tras tu QA propio; pesado: solo si el verificador dio PASS).**
   Commit descriptivo + **entrada en
   la bitácora de producto** (`CHANGELOG.md` — obligatoria si el cambio es visible
   para el usuario; ver "La bitácora de producto" abajo) → push → PR hacia `iOS`
   (`Closes FER-NN`, criterios verificados en "How it was tested") →
   **squash-merge a `iOS`** → **borra la rama** (`--delete-branch`) → **cierra el
   issue en `done` aquí mismo**, no después.
   - **El cierre del issue es parte de la entrega, no un trámite posterior.** Con
     `Closes FER-NN` en el PR, Multica puede pasarlo solo; **verifícalo** con
     `multica issue get FER-NN` y, si no se movió, `multica issue status FER-NN done`
     + comenta el link del PR. Un issue que se quedó en `in_progress` con su código
     ya en `iOS` es un semáforo que miente: la retro del 2026-08-28 encontró tres
     (FER-86, FER-33, FER-15), uno de ellos 26 días viejo. La regla nueva es que
     mergear y apagar el semáforo son **el mismo acto**.
   - **Gate de Design Lint (obligatorio, ambos carriles) antes del squash-merge.**
     El repo es privado en plan Free: GitHub NO puede imponer required checks, así
     que **tú eres el gate**. Corre
     `python3 Tools/check-design-drift.py --rules no-adhoc-font,no-radius-literal,no-opacity-literal Cenit/Screens Cenit/Onboarding`
     (más `no-hex` sobre todos los roots si tu diff toca UI) y confirma que sale ✅.
     Si sale rojo, **no mergees**: promueve el valor a un token de `CenitDesign` o
     anota `// token-exempt: <razón>`, y re-corre hasta verde. Esto ataja la deriva
     que CI (solo `Packages/**`) no ve — es como se coló FER-857 (#872), arreglado
     en #874. Verifica además con `gh pr checks <N>` que el job `lint` quedó verde.
10. **Limpieza final.** Sincroniza el checkout de build: `git -C ~/code/noop fetch origin`
    y `git -C ~/code/noop merge --ff-only origin/iOS` (si no puede fast-forward, avísale
    al usuario en vez de forzar). Reporta en lenguaje claro: qué cambió en la app, qué
    criterios quedaron verificados, y que el único paso manual restante es
    compilar/instalar en Xcode.
11. **Barrido de disco (obligatorio, un comando).**
    ```bash
    Tools/cleanup.sh --apply
    ```
    Poda los worktrees ya entregados y el DerivedData que dejaron atrás (~1 GB por
    worktree compilado). Corre primero sin `--apply` si quieres ver el simulacro.

    **No lo reimplementes a mano.** La receta inline que vivía aquí detectaba las ramas
    entregadas con `git merge-base --is-ancestor <rama> origin/iOS` — y ese chequeo es
    **ciego a todo squash-merge**, que es como se mergea *todo* en este repo: el squash
    reescribe los commits, así que la rama entregada nunca queda como ancestro de `iOS`.
    Por eso el barrido no atrapaba nada y se acumularon 22 worktrees / 7.9 GB sin que
    nadie lo viera (FER-194). La señal correcta, que `cleanup.sh` sí usa, es la que el
    propio flujo produce: **la rama tuvo upstream en `origin` y ya no está ahí** porque
    el merge la borró. El script conserva el worktree actual, el canónico, los `locked`,
    los que tienen cambios sin commitear, los que nunca se empujaron y los que siguen
    vivos en `origin` (otra sesión). Ver [[deriveddata-bloat-corruption]] y
    [[squash-merge-ancestry-lies]].

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
- **El usuario no aprobó el preview** de la pasada de UI (o pidió ajustes): itera
  el diseño con `/ui`, no codifiques la pantalla a ciegas.

## Qué NO hacer

- No implementes un issue ambiguo — regrésalo a `/pm`.
- No te salgas del alcance. Si encuentras otra cosa, créala como issue aparte (vía
  `/pm`), no la metas aquí.
- No reuses ni pises la rama de otra sesión; no trabajes en `iOS`.
- **En carril pesado, no te saltes el verificador independiente ni mergees sin su
  PASS.** Tu propio QA no autoriza el merge ahí — el gate del paso 8 sí. No le pases
  tu narrativa. (En carril ligero no hay paso 8: tu QA propio es el gate.)
- No mergees si el QA no pasó o si es de alto riesgo (ver "Cuándo PARAR").
- No repitas ni contradigas `CLAUDE.md` / `docs/CONTRIBUTING.md`; síguelos.
