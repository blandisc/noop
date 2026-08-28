#!/bin/bash
# Barrido de fin de trabajo: worktrees fósiles + DerivedData huérfano.
#
# POR QUÉ EXISTE (FER-194). El flujo mergea SIEMPRE con squash. Un squash-merge
# reescribe los commits, así que la rama mergeada NO queda como ancestro de
# `iOS`: `git merge-base --is-ancestor <rama> origin/iOS` responde "no" para
# TODA rama que pasó por el flujo normal. La receta anterior (inline en
# /implement) se apoyaba justo en ese `--is-ancestor`, así que era ciega a
# todos sus fósiles: 22 worktrees y 7.9 GB acumulados sin que nadie lo notara.
#
# LA SEÑAL CORRECTA es la que el propio flujo produce: al mergear se borra la
# rama de `origin` (`gh pr merge --delete-branch`). Entonces una rama local que
# TUVO upstream en origin y cuyo upstream YA NO EXISTE es, por construcción,
# una rama entregada. Eso es lo que podamos.
#
# GUARDIANES (un worktree se conserva si cualquiera aplica):
#   - es el worktree de esta sesión, o el checkout canónico, o la rama `iOS`
#   - está `locked`
#   - tiene cambios sin commitear
#   - su rama NUNCA tuvo upstream  → trabajo local que nadie empujó
#   - su rama SIGUE en `origin`    → trabajo en vuelo, posiblemente de otra sesión
#
# USO:
#   Tools/cleanup.sh            # simulacro: dice qué haría, no borra nada
#   Tools/cleanup.sh --apply    # ejecuta
#
# Es seguro correrlo con Xcode abierto y con otras sesiones trabajando.

set -euo pipefail

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1
[ "${1:-}" = "--dry-run" ] && APPLY=0

MAIN=~/code/noop
SELF="$(git rev-parse --show-toplevel 2>/dev/null || echo /nonexistent)"
DD=~/Library/Developer/Xcode/DerivedData

if [ $APPLY -eq 1 ]; then echo "== BARRIDO (--apply) =="; else echo "== SIMULACRO (sin --apply no se borra nada) =="; fi

# Los refs remotos deben estar frescos: "la rama ya no está en origin" es la señal.
git -C "$MAIN" fetch --prune --quiet origin 2>/dev/null || echo "aviso: no se pudo hacer fetch; el veredicto usa los refs locales"

podados=0
conservados=0

while read -r wt ref; do
  br="${ref##refs/heads/}"

  motivo=""
  [ "$br" = "iOS" ]                                   && motivo="es la rama iOS"
  [ "$wt" = "$SELF" ]                                 && motivo="es el worktree de esta sesión"
  [ "$wt" = "$MAIN" ]                                 && motivo="es el checkout canónico"
  if [ -z "$motivo" ] && [ -f "$(git -C "$MAIN" rev-parse --git-common-dir)/worktrees/$(basename "$wt")/locked" ]; then
    motivo="está locked"
  fi
  if [ -z "$motivo" ] && [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    motivo="tiene cambios sin commitear"
  fi

  if [ -z "$motivo" ]; then
    # La rama remota que ESTA rama local rastrea (ojo: puede llamarse distinto).
    up="$(git -C "$MAIN" config "branch.$br.merge" 2>/dev/null || true)"
    if [ -z "$up" ]; then
      motivo="nunca tuvo upstream (trabajo sin empujar)"
    elif git -C "$MAIN" show-ref --verify --quiet "refs/remotes/origin/${up##refs/heads/}"; then
      motivo="su rama sigue viva en origin (trabajo en vuelo)"
    fi
  fi

  if [ -n "$motivo" ]; then
    conservados=$((conservados + 1))
    echo "  conservado: $br — $motivo"
  else
    echo "  PODAR: $br  ($wt)"
    if [ $APPLY -eq 1 ]; then
      # `worktree remove` se niega solo si hay cambios sin commitear: red extra.
      if git -C "$MAIN" worktree remove "$wt" 2>/dev/null; then
        git -C "$MAIN" branch -D "$br" >/dev/null 2>&1 || true
        podados=$((podados + 1))
      else
        echo "    (git se negó a removerlo; se conserva)"
      fi
    fi
  fi
done < <(git -C "$MAIN" worktree list --porcelain | awk '/^worktree /{wt=$2} /^branch /{print wt" "$2}')

[ $APPLY -eq 1 ] && git -C "$MAIN" worktree prune

echo "worktrees: $podados podado(s), $conservados conservado(s)"

# Fósiles del rename Cénit: esas rutas ya no existen, es basura 100% segura.
if compgen -G "$DD/Strand-*" >/dev/null; then
  echo "  DerivedData fósil pre-rename: $(compgen -G "$DD/Strand-*" | wc -l | tr -d ' ') carpeta(s)"
  [ $APPLY -eq 1 ] && rm -rf "$DD"/Strand-*
fi

# Ya sin los worktrees, su DerivedData quedó huérfano y el podador lo ve.
if [ $APPLY -eq 1 ]; then
  "$(dirname "$0")/prune-deriveddata.sh"
else
  echo "  (con --apply correría Tools/prune-deriveddata.sh para el DerivedData huérfano)"
  du -sh "$DD" 2>/dev/null || true
fi
