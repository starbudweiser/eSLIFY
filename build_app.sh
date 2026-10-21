#!/bin/bash
# Construit eSLIFY.app à la racine du projet et supprime tous les fichiers temporaires.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/src/eSLIFY.py"
APP_NAME="eSLIFY"
ICON="$ROOT/assets/icon.icns"
PY="${PYTHON:-python3}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/eslify_build.XXXXXX")"

cleanup() {
  rm -rf "$TMP" "$ROOT/build" "$ROOT/$APP_NAME.spec" "$ROOT/src/__pycache__"
}
trap cleanup EXIT

[ -f "$SRC" ] || { echo "Erreur : $SRC introuvable." >&2; exit 1; }
"$PY" -c "import PyInstaller, PyQt6" 2>/dev/null || { echo "Erreur : installez PyInstaller et PyQt6 (pip install pyinstaller PyQt6)." >&2; exit 1; }

ICON_ARGS=()
[ -f "$ICON" ] && ICON_ARGS=(--icon "$ICON")
[ -f "$ROOT/assets/icon.png" ] && ICON_ARGS+=(--add-data "$ROOT/assets/icon.png:assets")

rm -rf "$ROOT/$APP_NAME.app"
"$PY" -m PyInstaller --noconfirm --clean --windowed --name "$APP_NAME" ${ICON_ARGS[@]+"${ICON_ARGS[@]}"} \
  --osx-bundle-identifier "local.stephan.eslify" \
  --distpath "$TMP/dist" --workpath "$TMP/work" --specpath "$TMP/spec" \
  "$SRC"

[ -d "$TMP/dist/$APP_NAME.app" ] || { echo "Erreur : app non générée." >&2; exit 1; }
"$(cd "$ROOT/.." && pwd)/_tools/sign_app.sh" "$TMP/dist/$APP_NAME.app" 1.0.0  # signature stable (_tools)
mv "$TMP/dist/$APP_NAME.app" "$ROOT/$APP_NAME.app"
echo "OK : $ROOT/$APP_NAME.app"
