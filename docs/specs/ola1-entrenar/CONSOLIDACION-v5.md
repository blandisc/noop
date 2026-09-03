# Consolidación v5 · Ola 1 · tras ronda 4 (Grok: 5 cerrados, 4 nuevos: 3 medios, 1 bajo) · 2026-09-02

**Manda sobre v4, v3, v2, v1 y los specs.** Solo agrega decisiones sobre N13–N16.

## A · Decisiones ronda 4
| Id | Decisión |
|---|---|
| N13 copy que promete veredicto | Se tachan las tres frases. **ux-C Listo:** solo «N sesiones entran a tu carga» (o el copy N = 0), sin frase de veredicto. **ux-C Relación con ①:** «entran a Carga y al ACWR etiquetadas; el veredicto no cambia por la carga hasta que la carga vote (Q12)». **ux-A edge 9:** «La Carga recalcula sola; el veredicto solo cambia si cambian sus otras señales». Regla transversal de copy: **ninguna superficie de la ola 1 dice que una sesión cambia el veredicto.** |
| N14 Q11 vs Q12 | **Q11 se retira, absorbida por Q12.** La única pregunta viva sobre el veredicto es Q12 (rec.: la carga no vota en la ola 1; issue propio «la carga vota» como primera pieza de la ola 1b). |
| N15 `mode` en espejo y contador | Amplía E21: `mirrorAcrossRoundsIfSuperset` y `roundsAreEven` incluyen `mode`; `recetaCount` (y cualquier clave de igualdad de receta) incluye `mode`. Tests: AMRAP en última serie → receta abierta y contador ≠ «1» cuando solo difiere el modo; el espejo de superserie propaga `mode`. |
| N16 tecla «máx» | «máx» reutiliza la tecla de acción inferior-derecha del keypad (`confirmSet`), visible solo con `field == .repsTop` en una serie de trabajo; en piso y peso sigue oculta. Sin quinta tecla ni barra de accesorios. |

## B · Enmiendas (nuevas)
E25 **ux-C Listo y Relación con ①; ux-A edge 9:** copy de N13.
E26 **E21 ampliada:** N15 y N16.

## C · Bloque de CA sustituidos (se añade a v4 §C)
| Spec · CA | Texto viejo | Sustituto |
|---|---|---|
| ux-C · Listo (copy) | «Tu veredicto de mañana puede cambiar» | Solo el conteo N de N6; sin frase de veredicto. |
| ux-C · Relación con ① | «el veredicto de mañana puede moverse» | «entran a Carga y al ACWR etiquetadas; el veredicto no cambia por la carga (Q12)». |
| ux-A · edge 9 | «Carga y veredicto recalculan solos» | «La Carga recalcula sola». |

## D · Preguntas al dueño (lista final)
Q1 Subida en 1 sesión con Q ≥ 2 · Q2 contador solo con semanas entrenadas · Q3 semana ligera = solo volumen por default (×0,5), opción con peso al −7,5 % · Q4 cuatro motores = plantillas existentes con semanas · Q6 interruptor por ejercicio, apagado en rutinas existentes · Q7 celda AMRAP vacía · Q8 «Programa» fuera del first-run · Q9 sin rutinas desde nombres importados · Q10 la semana ligera cambia kicker y meta del héroe sin estado nuevo · **Q12 la carga no vota en la ola 1; issue propio inmediato para que vote (gate /cso)**. Q5 y Q11 retiradas.

## E · Estado
Bloqueantes 0 · Altas 0 · Medias abiertas 0 (todas decididas aquí). Pendiente: confirmación de Grok (ronda 5).
