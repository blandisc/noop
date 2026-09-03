# Ronda 5 · revisor adversarial (cierre N13–N16 + pasada final)

Base: `CONSOLIDACION-v5.md` manda sobre v4/v3/v2/v1/specs. Enmiendas E (v2–v5) y bloques C de v4/v5 no se re-reportan; sí se audita si v5 cierra de verdad y si queda algo vivo fuera de lo sustituido.

## Cierre de la ronda 4

| Id | Veredicto | Una línea |
|---|---|---|
| N13 | **CERRADO** | E25 + bloque C: se tachan Listo / Relación con ① / ux-A edge 9; regla transversal: ninguna superficie de ola 1 dice que una sesión cambia el veredicto. |
| N14 | **CERRADO** | Q11 retirada, absorbida por Q12; lista D final solo deja Q12 viva sobre el veredicto (carga no vota en ola 1). |
| N15 | **CERRADO** | E26 amplía E21: `mirrorAcrossRoundsIfSuperset`, `roundsAreEven` y `recetaCount` incluyen `mode` + tests. |
| N16 | **CERRADO** | E26: «máx» reusa `confirmSet` (inferior-derecha), solo con `field == .repsTop` en serie de trabajo. |

## Pasada con lupa (sin hallazgos nuevos)

- **Frases que prometen que una sesión cambia el veredicto:** las tres de N13 siguen en el texto crudo de `ux-C`/`ux-A`, pero quedan **sustituidas** por E25 + bloque C de v5; no se re-reportan. Fuera de ese bloque no aparece otra promesa equivalente (BRIEF, ux-B, arq-A/B, C9/A6 hablan de Carga/ACWR, no de voltear el veredicto). Código sigue alineado: `Preparedness.swift:678` — el eje `load` «never flips the verdict».
- **Contradicciones v5 vs lo anterior:** ninguna que importe. Q11×Q12 queda resuelta; E22/N10 siguen mandando sobre A·H9 de v2/v3; E26 completa el hueco de mode que N15 abrió. Diferencia menor A vs bloque C en el largo del sustituto de edge 9 (A menciona «otras señales»; C solo «La Carga recalcula sola») — C es el contrato de QA y es el más seguro; no sube a hallazgo.
- **CA imposibles:** los que N11 listó ya están en el bloque C canónico de v4 (+ adiciones de v5). No aparece un CA nuevo imposible fuera de esa lista.
- Solo quedarían matices **BAJA** de redacción entre A y C; no se inflan.

## Resumen

- Ronda 4: **CERRADO 4** (N13–N16) · **PARCIAL 0** · **ABIERTO 0**
- Nuevos por severidad: **BLOQUEANTE 0** · **ALTA 0** · **MEDIA 0** · **BAJA 0** (total nuevos: 0)
- Quedan solo cosas BAJA (o ninguna): la lupa no eleva nada; el requerimiento de ola 1 cierra limpio en papel.

HALLAZGOS NUEVOS: 0

CONVERGE: si

## Veredicto final

El requerimiento de ola 1 quedó sólido: motor sin votante de carga (Q12), copy alineado a esa verdad, editor AMRAP con `mode` extremo a extremo, y CA sustituidos en un bloque canónico. La cadena v2→v5 ya no deja recomendaciones opuestas ni promesas de veredicto en superficies de producto. El riesgo residual más grande de cara a `/implement` no es de diseño: es ejecutar E21/E26 y el overlay/calibración sin reintroducir un votante de carga ni copy de Listo que prometa lo que `Preparedness.load` no hace — más el issue ola 1b «la carga vota» (/cso), que sigue fuera a propósito.
