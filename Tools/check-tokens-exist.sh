#!/bin/zsh
# check-tokens-exist.sh — ¿existe cada token Liquid que usa el diff? (FER-308, retro de FER-299)
# Un token inventado (`LiquidColor.papel`, `LiquidSpace.hairline`, `.liquidGlass(.tarjeta)`) solo lo
# cazaba el build de app (8 min). Esto tarda segundos y no compila nada.
# Uso: Tools/check-tokens-exist.sh            → símbolos del diff contra el merge-base con origin/iOS
#      Tools/check-tokens-exist.sh <archivos> → símbolos de esos archivos
set -u
cd "$(git rev-parse --show-toplevel)"
PKG=Packages/CenitDesign/Sources/CenitDesign
if [ $# -gt 0 ]; then SRC=$(cat "$@"); else
  MB=$(git merge-base origin/iOS HEAD 2>/dev/null || echo HEAD~1)
  SRC=$(git diff "$MB" -U0 -- 'Cenit/*.swift' 'CenitApp/*.swift' 'Cenit/**/*.swift' 'CenitApp/**/*.swift' | grep '^+' | grep -v '^+++')
fi
fail=0
for sym in $(echo "$SRC" | grep -oE '\bLiquid(Color|Space|Type|Radius|Motion|Control|Elevation)\.[A-Za-z0-9_]+' | sort -u); do
  fam=${sym%%.*}; name=${sym#*.}
  # Solo cuenta si el miembro vive en los archivos que declaran/extienden esa familia (un `case papel`
  # de OutlineCapsule no valida `LiquidColor.papel`).
  files=$(grep -rlE "(enum|extension) $fam\b" "$PKG")
  echo "$files" | xargs grep -qE "static (let|var|func) $name\b" || { echo "❌ $sym no existe en $PKG"; fail=1; }
done
for rec in $(echo "$SRC" | grep -oE '\.liquidGlass\(\.[A-Za-z0-9_]+' | sed -E 's/.*\(\.//' | sort -u); do
  grep -qE "case $rec\b" "$PKG/LiquidGlass/LiquidGlassRecipes.swift" || { echo "❌ .liquidGlass(.$rec) no es una receta (ver LiquidGlassRecipes.swift)"; fail=1; }
done
[ $fail -eq 0 ] && echo "✅ todos los tokens Liquid del diff existen"
exit $fail
