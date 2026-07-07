# Guía de estilo — nombres de ejercicio es-MX (FER-795)

La traducción de los **nombres** del catálogo (paso 3 del bake) sigue estas reglas. Es la fuente
de verdad para cualquier retraducción futura: pégala en el prompt del traductor (LLM o humano).

## Reglas

1. **Capitalización tipo oración, uniforme.** Primera letra en mayúscula, el resto en minúscula
   salvo nombres propios ("Press de banca con barra", "Press Arnold con mancuernas"). Nunca
   "press de banca…" ni Title Case completo.
2. **Terminología de gym mexicano.** Como lo diría un usuario de gym en México:
   press, curl, remo, jalón, peso muerto, sentadilla, zancada (no "estocada"), fondos,
   dominada, elevación, encogimiento, plancha, puente, burpee, crunch.
   Los anglicismos establecidos se quedan como préstamo: press, curl, burpee, crunch, kettlebell
   (o "pesa rusa", pero consistente), hip thrust, sissy squat.
3. **Sin literalismos absurdos.** Nada de traducir el nombre-metáfora palabra por palabra
   ("impossible dips" ≠ "fondos imposibles"). Si el nombre EN es un término de arte sin
   equivalente usado en español, **se conserva en inglés** ("Pistol squat", "Superman",
   "Bird dog", "Dead bug") — mejor un préstamo reconocible que una traducción que nadie usa.
4. **Equipo con fraseo consistente**, siempre al final del nombre cuando aplica:
   - `con barra` / `con barra EZ` / `con mancuernas` (plural) / `con mancuerna` (si es a una mano)
   - `en máquina Smith` / `en máquina` / `en polea` / `con banda` / `con pesa rusa` / `en trineo`
   - peso corporal: sin sufijo (no "con peso corporal" salvo que desambigüe).
5. **Estructura**: `<Movimiento> <variante> <equipo>` — "Press de banca inclinado con barra",
   "Remo inclinado con mancuernas". La variante (inclinado, declinado, agarre cerrado, a una
   pierna, sentado, de pie) va entre el movimiento y el equipo.
6. **Anatomía en español llano**: pantorrilla, femoral, glúteo, dorsal, trapecio, antebrazo.
7. **Sin adornos**: nada de "variante clásica", "estilo suave" u otra paja que el nombre EN no
   justifique. El nombre es un identificador, no una descripción.

## Proceso

Los nombres se retraducen como pares `{en → es}` en archivos `batch-*.json` (formato del paso 3
del README). El overlay se reensambla con `build_es_overlay.py <dir_actual> <dir_nombres>` — el
directorio de nombres al final para que sobreescriba, y el batch "actual" preserva las
instrucciones ya traducidas.

## Verificación (criterios FER-795)

- 0 nombres iniciando en minúscula: `python3 -c "import json;print(sum(1 for e in json.load(open('../../Packages/StrandTraining/Sources/StrandTraining/Resources/exercises.es.json')) if e['name'][:1].islower()))"`
- 1500 ids, cero entradas perdidas (lo reporta `build_es_overlay.py`).
- `swift test` verde en `Packages/StrandTraining` y `Packages/StrandImport`.
