#!/usr/bin/env bash
# Compile browboxs-desktop (Tauri shell only) on the CURRENT OS and inject into
# an extracted kit stage. Public pack-and-test runners call this; it must never
# cargo-build agent/server.
#
# Usage:
#   bash scripts/build-desktop-from-kit.sh --stage /path/to/browboxs [--work /path/to/kit-root]
#
# Env:
#   DESKTOP_SHELL   path to desktop-shell/ (package.json + src-tauri)
#   FORCE_DESKTOP=1 overwrite existing browboxs-desktop
set -euo pipefail

STAGE=""
WORK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE="$2"; shift 2 ;;
    --work) WORK="$2"; shift 2 ;;
    -h|--help) sed -n '1,20p' "$0"; exit 0 ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$STAGE" ] || [ ! -d "$STAGE/bin" ]; then
  echo "ERROR: --stage must be extracted kit browboxs/ directory" >&2
  exit 1
fi
STAGE="$(cd "$STAGE" && pwd)"
if [ -z "$WORK" ]; then
  WORK="$(cd "$STAGE/.." && pwd)"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHELL_DIR="${DESKTOP_SHELL:-}"
if [ -z "$SHELL_DIR" ]; then
  for d in \
    "$ROOT/desktop-shell" \
    "$ROOT/packaging/public-app-releases/desktop-shell"; do
    if [ -f "$d/src-tauri/tauri.conf.json" ]; then SHELL_DIR="$d"; break; fi
  done
fi
if [ -z "$SHELL_DIR" ] || [ ! -f "$SHELL_DIR/src-tauri/Cargo.toml" ]; then
  echo "ERROR: desktop-shell not found (expected $ROOT/desktop-shell)" >&2
  exit 1
fi
SHELL_DIR="$(cd "$SHELL_DIR" && pwd)"

EXE=""
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT) EXE=".exe" ;;
esac
if [ -f "$STAGE/bin/browboxs-agent.exe" ]; then EXE=".exe"; fi

AGENT="$STAGE/bin/browboxs-agent${EXE}"
SERVER="$STAGE/bin/browboxs-server${EXE}"
test -f "$AGENT" || { echo "ERROR: missing $AGENT" >&2; exit 1; }
test -f "$SERVER" || { echo "ERROR: missing $SERVER" >&2; exit 1; }
test -f "$STAGE/ui/desktop/index.html" || { echo "ERROR: kit missing ui/desktop/index.html" >&2; exit 1; }

KIT_TRIPLE=""
if [ -f "$WORK/TRIPLE.txt" ]; then
  KIT_TRIPLE=$(tr -d ' \n\r' <"$WORK/TRIPLE.txt")
fi
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: need $1" >&2; exit 1; }; }
need_cmd cargo
need_cmd rustc
need_cmd npm

HOST_TRIPLE=$(rustc -vV | awk '/^host:/{print $2}')
# Windows kits are often *-windows-gnu from Linux cross; runner compiles the
# shell as native MSVC. Sidecar filenames follow the DESKTOP rust target.
DESKTOP_TARGET="$KIT_TRIPLE"
case "$KIT_TRIPLE" in
  *-pc-windows-gnu)
    DESKTOP_TARGET="$HOST_TRIPLE"
    ;;
  "")
    DESKTOP_TARGET="$HOST_TRIPLE"
    ;;
esac
if [ -z "$DESKTOP_TARGET" ]; then
  DESKTOP_TARGET="$HOST_TRIPLE"
fi

echo "== build-desktop-from-kit =="
echo "  stage=$STAGE"
echo "  shell=$SHELL_DIR"
echo "  kit_triple=${KIT_TRIPLE:-unknown}"
echo "  desktop_target=$DESKTOP_TARGET"
echo "  host=$HOST_TRIPLE"

if [ "$DESKTOP_TARGET" != "$HOST_TRIPLE" ]; then
  rustup target add "$DESKTOP_TARGET"
fi

rm -rf "$SHELL_DIR/dist"
mkdir -p "$SHELL_DIR/dist" "$SHELL_DIR/src-tauri/binaries"
cp -a "$STAGE/ui/desktop/." "$SHELL_DIR/dist/"
# Sidecar names must match the target we compile the shell for.
cp -f "$AGENT" "$SHELL_DIR/src-tauri/binaries/browboxs-agent-${DESKTOP_TARGET}${EXE}"
cp -f "$SERVER" "$SHELL_DIR/src-tauri/binaries/browboxs-server-${DESKTOP_TARGET}${EXE}"
chmod +x "$SHELL_DIR/src-tauri/binaries/"* 2>/dev/null || true

(
  cd "$SHELL_DIR"
  if [ -f package-lock.json ]; then npm ci --ignore-scripts || npm ci; else npm install --no-audit --no-fund; fi
  # --no-bundle: we only need the desktop binary; pack-kit-to-release makes tar/deb.
  TAURI_ARGS=(build --no-bundle --target "$DESKTOP_TARGET")
  if [ "${BROWBOX_DESKTOP_WDIO:-1}" = "1" ]; then
    TAURI_ARGS+=(--features wdio-e2e)
    echo "  wdio-e2e=1 (embedded WebDriver; macOS + env TAURI_WEBDRIVER_PORT)"
  fi
  npx tauri "${TAURI_ARGS[@]}"
)

OUT=""
for cand in \
  "$SHELL_DIR/src-tauri/target/${DESKTOP_TARGET}/release/browboxs-desktop${EXE}" \
  "$SHELL_DIR/src-tauri/target/release/browboxs-desktop${EXE}"; do
  if [ -f "$cand" ]; then OUT="$cand"; break; fi
done
if [ -z "$OUT" ]; then
  echo "ERROR: tauri build produced no browboxs-desktop" >&2
  find "$SHELL_DIR/src-tauri/target" -name "browboxs-desktop*" 2>/dev/null | head -20 || true
  exit 1
fi
cp -f "$OUT" "$STAGE/bin/browboxs-desktop${EXE}"
chmod +x "$STAGE/bin/browboxs-desktop${EXE}" 2>/dev/null || true
echo "OK desktop injected: $STAGE/bin/browboxs-desktop${EXE} ($(wc -c <"$STAGE/bin/browboxs-desktop${EXE}" | tr -d ' ') bytes)"
