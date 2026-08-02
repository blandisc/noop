#!/bin/bash
# Tools/verify.sh — el comando único de verificación de Cénit.
#
# Uso:
#   Tools/verify.sh              # auto: linters + paquetes tocados + build de app si tocaste la capa app
#   Tools/verify.sh quick        # solo linters (rápido; NO cuenta como verificación para el stop-gate)
#   Tools/verify.sh package <N>  # build + test de un paquete específico
#   Tools/verify.sh packages     # build + test de todos los paquetes tocados vs origin/iOS
#   Tools/verify.sh app          # xcodegen + build-for-testing (compila app + targets de test, no ejecuta)
#   Tools/verify.sh app-tests    # corre CenitUnitTests en simulador (pesado; apaga el simulador al final)
#
# Encapsula la coreografía de recursos de esta Mac (16 GB / 8 cores): espera a que no haya
# otro build corriendo, -jobs 4 siempre, prune de DerivedData antes, simctl shutdown después.
# En éxito (salvo `quick`) escribe un stamp que el Stop-hook de Claude Code usa como evidencia.
set -u
root=$(git rev-parse --show-toplevel) || exit 1
cd "$root" || exit 1
mode=${1:-auto}

fail() { echo "✋ verify: $*" >&2; exit 1; }

stamp_ok() {
  date +%s > "$(git rev-parse --git-dir)/cenit-verify-stamp"
}

# Archivos cambiados vs la base de iOS + working tree (sin duplicados).
changed_files() {
  {
    base=$(git merge-base origin/iOS HEAD 2>/dev/null) && git diff --name-only --diff-filter=ACM "$base"
    git status --porcelain | sed 's/^...//' | sed 's/^"\(.*\)"$/\1/'
  } | sort -u
}

wait_idle() {
  # Nunca dos builds a la vez (regla #1 del CLAUDE.md). Tope: 30 min.
  waited=0
  while pgrep -q swift-frontend; do
    [ "$waited" -eq 0 ] && echo "verify: hay otro build corriendo (swift-frontend); esperando a que la máquina quede libre…"
    sleep 30; waited=$((waited + 30))
    [ "$waited" -ge 1800 ] && fail "30 min esperando un build ajeno; probablemente el usuario está en Xcode. Reintenta después."
  done
}

run_lint() {
  files=$(changed_files | grep -E '\.swift$' || true)
  if [ -n "$files" ] && [ -f Tools/check-design-drift.py ]; then
    ok=0
    # shellcheck disable=SC2086
    python3 Tools/check-design-drift.py --rules no-hex $files || ok=1
    screens=$(printf '%s\n' $files | grep -E '^Cenit/(Screens|Onboarding)/' || true)
    if [ -n "$screens" ]; then
      # shellcheck disable=SC2086
      python3 Tools/check-design-drift.py --rules no-adhoc-font,no-radius-literal,no-opacity-literal $screens || ok=1
    fi
    [ "$ok" -ne 0 ] && fail "deriva del sistema de diseño (token de StrandDesign o « // token-exempt: <motivo> »)."
  fi
  if changed_files | grep -qE 'Localizable\.xcstrings$' && [ -f Tools/check-xcstrings-cycles.py ]; then
    python3 Tools/check-xcstrings-cycles.py || fail "ciclo en un String Catalog (FER-395)."
  fi
  echo "verify: linters OK"
}

run_package() {
  name=$1
  [ -d "Packages/$name" ] || fail "no existe Packages/$name"
  echo "verify: swift build + test — $name"
  (cd "Packages/$name" && swift build && swift test) || fail "Packages/$name falló build o tests."
}

touched_packages() {
  changed_files | grep -oE '^Packages/[^/]+' | sort -u | sed 's|^Packages/||'
}

app_touched() {
  changed_files | grep -qE '^(Cenit|CenitApp|CenitShared|CenitWidgets|CenitUnitTests|CenitUITests)/|^project\.yml$'
}

run_app_build() {
  wait_idle
  [ -x Tools/prune-deriveddata.sh ] && Tools/prune-deriveddata.sh
  xcodegen generate || fail "xcodegen generate falló."
  # build-for-testing: compila también CenitUnitTests/CenitUITests (mismo racional que ios-app.yml).
  xcodebuild build-for-testing \
    -project Cenit.xcodeproj -scheme Cenit \
    -destination 'generic/platform=iOS Simulator' -configuration Debug \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" ASSETCATALOG_COMPILER_APPICON_NAME="" \
    -jobs 4 || fail "la app (o sus targets de test) no compila."
  echo "verify: app + targets de test compilan OK"
}

run_app_tests() {
  run_app_build
  sim=$(xcrun simctl list devices available | grep -oE 'iPhone [0-9A-Za-z ]+' | head -1 | sed 's/ *$//')
  [ -n "$sim" ] || fail "no hay simulador iPhone disponible."
  echo "verify: CenitUnitTests en «$sim»"
  xcodebuild test-without-building \
    -project Cenit.xcodeproj -scheme Cenit \
    -destination "platform=iOS Simulator,name=$sim" \
    -only-testing:CenitUnitTests -jobs 4
  status=$?
  xcrun simctl shutdown all 2>/dev/null
  [ $status -ne 0 ] && fail "CenitUnitTests en rojo."
  echo "verify: CenitUnitTests OK"
}

case "$mode" in
  quick)
    run_lint ;;                                  # sin stamp: lint solo no es verificación completa
  package)
    [ $# -ge 2 ] || fail "uso: verify.sh package <Nombre>"
    run_lint; run_package "$2"; stamp_ok ;;
  packages)
    run_lint
    pkgs=$(touched_packages)
    if [ -z "$pkgs" ]; then echo "verify: ningún paquete tocado"; else
      for p in $pkgs; do run_package "$p"; done
    fi
    stamp_ok ;;
  app)
    run_lint; run_app_build; stamp_ok ;;
  app-tests)
    run_lint; run_app_tests; stamp_ok ;;
  auto)
    run_lint
    pkgs=$(touched_packages)
    for p in $pkgs; do run_package "$p"; done
    if app_touched; then run_app_build; fi
    stamp_ok
    echo "verify: ✅ todo verde"
    ;;
  *) fail "modo desconocido: $mode (usa quick|package|packages|app|app-tests|auto)" ;;
esac
