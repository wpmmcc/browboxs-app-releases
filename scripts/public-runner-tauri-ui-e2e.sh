#!/usr/bin/env bash
# S3b product UI gate: full workbench against **installed** browboxs-desktop WebView.
# Linux/Win: tauri-driver + OS native driver. macOS: embedded tauri-plugin-wdio-webdriver.
#
# Usage:
#   bash scripts/public-runner-tauri-ui-e2e.sh /path/to/install-root
set -euo pipefail

ROOT_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
INSTALL="${1:-${INSTALL_ROOT:-}}"
if [ -z "$INSTALL" ]; then
  echo "usage: $0 <install-root>" >&2
  exit 2
fi
INSTALL="$(cd "$INSTALL" && pwd)"
REPORT="${BROWBOX_TAURI_E2E_REPORT:-${TMPDIR:-/tmp}/bb-tauri-e2e-$$}"
mkdir -p "$REPORT"
OS="$(uname -s 2>/dev/null || echo unknown)"
STRICT="${BROWBOX_TAURI_E2E_STRICT:-}"
E2E_SUITE="${BROWBOX_TAURI_E2E_SUITE:-full}"
if [ -z "$STRICT" ]; then
  case "$OS" in
    Linux*|Darwin*) STRICT=1 ;;
    *) STRICT=0 ;;
  esac
fi
E2E_DRIVER="${BROWBOX_E2E_DRIVER:-}"
if [ -z "$E2E_DRIVER" ]; then
  case "$OS" in
    Darwin*|Linux*) E2E_DRIVER=embedded ;;
    *) E2E_DRIVER=external ;;
  esac
fi

PASS=0; FAIL=0; WARN=0
ok()   { PASS=$((PASS+1)); echo "PASS  $*"; echo "PASS  $*" >>"$REPORT/summary.txt"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL  $*"; echo "FAIL  $*" >>"$REPORT/summary.txt"; }
warn() { WARN=$((WARN+1)); echo "WARN  $*"; echo "WARN  $*" >>"$REPORT/summary.txt"; }

finish() {
  echo "== RESULT PASS=$PASS FAIL=$FAIL WARN=$WARN STRICT=$STRICT suite=$E2E_SUITE ==" | tee -a "$REPORT/summary.txt"
  if [ "$FAIL" -gt 0 ]; then
    if [ "$STRICT" = "1" ]; then
      return 1
    fi
    echo "non-strict: FAIL lines do not fail this OS cell"
    return 0
  fi
  return 0
}

echo "== public-runner-tauri-ui-e2e (S3b Tauri WebView) =="
echo "  install=$INSTALL"
echo "  report=$REPORT"
echo "  os=$OS strict=$STRICT suite=$E2E_SUITE driver=$E2E_DRIVER"

case "$OS" in
  Darwin*)
    if [ "$E2E_DRIVER" != "embedded" ]; then
      warn "macOS requires BROWBOX_E2E_DRIVER=embedded (wdio-e2e feature in desktop binary)"
    fi
    ;;
esac

EXE=""
case "$OS" in
  MINGW*|MSYS*|CYGWIN*) EXE=".exe" ;;
esac
if [ -f "$INSTALL/bin/browboxs-desktop.exe" ]; then EXE=".exe"; fi
DESKTOP="$INSTALL/bin/browboxs-desktop${EXE}"
AGENT="$INSTALL/bin/browboxs-agent${EXE}"

if [ ! -f "$DESKTOP" ]; then
  bad "browboxs-desktop missing at $DESKTOP"
  finish
  exit $?
fi
ok "desktop binary present"
chmod +x "$DESKTOP" "$AGENT" 2>/dev/null || true

# GitHub macos-latest is arm64; the x86_64 desktop runs under Rosetta.
# WKWebView execute/sync is unreliable there — keep native aarch64 as the hard gate.
if [[ "$OS" == Darwin* ]]; then
  HOST_ARCH="$(uname -m)"
  if file -b "$DESKTOP" 2>/dev/null | grep -q 'x86_64' && [ "$HOST_ARCH" = "arm64" ]; then
    warn "Rosetta: x86_64 desktop on arm64 runner — S3b non-strict (native aarch64 remains hard gate)"
    STRICT=0
  fi
fi

export PATH="${HOME}/.cargo/bin:${PATH}"
if [ "$E2E_DRIVER" = "external" ]; then
  if ! command -v tauri-driver >/dev/null 2>&1; then
    bad "tauri-driver not on PATH (install with cargo install tauri-driver)"
    finish
    exit $?
  fi
  ok "tauri-driver $(command -v tauri-driver)"
else
  ok "embedded webdriver (TAURI_WEBDRIVER_PORT=${TAURI_WEBDRIVER_PORT:-4445})"
fi

case "$OS" in
  Linux*)
    if [ "$E2E_DRIVER" = "external" ]; then
    if ! command -v WebKitWebDriver >/dev/null 2>&1; then
      bad "WebKitWebDriver missing (apt install webkit2gtk-driver)"
      finish
      exit $?
    fi
    ok "WebKitWebDriver $(command -v WebKitWebDriver)"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    if ! command -v msedgedriver >/dev/null 2>&1 && [ ! -f ./msedgedriver.exe ]; then
      warn "msedgedriver not on PATH — Windows WebView e2e will likely fail"
    else
      ok "msedgedriver present"
    fi
    ;;
esac

E2E_DIR=""
for d in "$ROOT_SCRIPT/e2e-tauri" "$ROOT_SCRIPT/../e2e-tauri"; do
  if [ -f "$d/full_workbench_installed.py" ] || [ -f "$d/wdio.conf.js" ]; then
    E2E_DIR="$d"
    break
  fi
done
if [ -z "$E2E_DIR" ]; then
  bad "e2e-tauri/ missing (need full_workbench_installed.py)"
  finish
  exit $?
fi
ok "e2e-tauri dir $E2E_DIR"

pkill -f "browboxs-desktop" 2>/dev/null || true
pkill -f "tauri-driver" 2>/dev/null || true
pkill -f "WebKitWebDriver" 2>/dev/null || true
sleep 0.5

export BROWBOX_PREFIX="$INSTALL"
export BROWBOX_INSTALL_ROOT="$INSTALL"
export BROWBOX_DESKTOP="$DESKTOP"
export BROWBOX_AGENT_BIN="$AGENT"
export BROWBOX_TAURI_E2E_REPORT="$REPORT"
export BROWBOX_E2E_LOG_DIR="$REPORT"
export BROWBOX_AGENT_PORT="${BROWBOX_AGENT_PORT:-18985}"
export BROWBOX_E2E_KEEP_SPLASH=1
export BROWBOX_DRY_RUN="${BROWBOX_DRY_RUN:-1}"
export BROWBOX_E2E_DRIVER="$E2E_DRIVER"
export TAURI_DRIVER="$(command -v tauri-driver 2>/dev/null || true)"
export PYTHONUNBUFFERED=1
if [ "$E2E_DRIVER" = "embedded" ]; then
  export TAURI_WEBDRIVER_PORT="${TAURI_WEBDRIVER_PORT:-4445}"
else
  unset TAURI_WEBDRIVER_PORT
  export TAURI_DRIVER_PORT="${TAURI_DRIVER_PORT:-4444}"
  export TAURI_NATIVE_PORT="${TAURI_NATIVE_PORT:-4445}"
fi

run_full_workbench() {
  if [ ! -f "$E2E_DIR/full_workbench_installed.py" ]; then
    bad "full_workbench_installed.py missing"
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    bad "python3 required for full workbench e2e"
    return 1
  fi
  python3 "$E2E_DIR/full_workbench_installed.py" >"$REPORT/full-workbench.log" 2>&1
}

run_wdio_smoke() {
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    bad "node/npm required for wdio smoke"
    return 1
  fi
  (
    cd "$E2E_DIR"
    if [ ! -d node_modules/@wdio/cli ]; then
      npm install --no-audit --no-fund
    fi
  ) >"$REPORT/npm.log" 2>&1 || return 1
  if [[ "$OS" == Linux* ]] && command -v xvfb-run >/dev/null 2>&1; then
    (cd "$E2E_DIR" && xvfb-run -a -s "-screen 0 1440x900x24" npx wdio run wdio.conf.js) \
      >"$REPORT/wdio-smoke.log" 2>&1
  else
    (cd "$E2E_DIR" && npx wdio run wdio.conf.js) >"$REPORT/wdio-smoke.log" 2>&1
  fi
}

set +e
EC=0
if [ "$E2E_SUITE" = "smoke" ]; then
  run_wdio_smoke
  EC=$?
  tail -60 "$REPORT/wdio-smoke.log" 2>/dev/null || true
  if [ "$EC" -eq 0 ]; then
    ok "wdio smoke WebView e2e"
  else
    bad "wdio smoke WebView e2e exit=$EC"
  fi
else
  if [[ "$OS" == Linux* ]] && command -v xvfb-run >/dev/null 2>&1; then
    XVFB_ENV=(
      BROWBOX_PREFIX="$INSTALL" BROWBOX_INSTALL_ROOT="$INSTALL"
      BROWBOX_DESKTOP="$DESKTOP" BROWBOX_AGENT_BIN="$AGENT"
      BROWBOX_E2E_LOG_DIR="$REPORT" BROWBOX_TAURI_E2E_REPORT="$REPORT"
      BROWBOX_AGENT_PORT="${BROWBOX_AGENT_PORT:-18985}"
      BROWBOX_E2E_KEEP_SPLASH=1 BROWBOX_DRY_RUN="${BROWBOX_DRY_RUN:-1}"
      BROWBOX_E2E_DRIVER="$E2E_DRIVER"
      TAURI_DRIVER="$(command -v tauri-driver 2>/dev/null || true)"
      PYTHONUNBUFFERED=1
    )
    if [ "$E2E_DRIVER" = "embedded" ]; then
      XVFB_ENV+=(TAURI_WEBDRIVER_PORT="${TAURI_WEBDRIVER_PORT:-4445}")
      xvfb-run -a -s "-screen 0 1440x900x24" \
        env "${XVFB_ENV[@]}" python3 "$E2E_DIR/full_workbench_installed.py" \
        >"$REPORT/full-workbench.log" 2>&1
    else
      XVFB_ENV+=(TAURI_DRIVER_PORT="${TAURI_DRIVER_PORT:-4444}" TAURI_NATIVE_PORT="${TAURI_NATIVE_PORT:-4445}")
      xvfb-run -a -s "-screen 0 1440x900x24" \
        env -u TAURI_WEBDRIVER_PORT "${XVFB_ENV[@]}" python3 "$E2E_DIR/full_workbench_installed.py" \
        >"$REPORT/full-workbench.log" 2>&1
    fi
    EC=$?
  else
    run_full_workbench
    EC=$?
  fi
  tail -100 "$REPORT/full-workbench.log" 2>/dev/null || true
  if [ -f "$REPORT/SUMMARY.json" ]; then
    python3 - <<PY >>"$REPORT/summary.txt"
import json
from pathlib import Path
p = Path("$REPORT/SUMMARY.json")
if p.is_file():
    s = json.loads(p.read_text())
    print(f"full_workbench pass={s.get('pass')} fail={s.get('fail')}")
    for r in s.get("results", []):
        mark = "PASS" if r.get("ok") else "FAIL"
        name = r.get("name", "?")
        detail = r.get("detail", "")
        line = f"{mark}  {name}" + (f" · {detail}" if detail else "")
        print(line)
PY
    FP=$(python3 -c "import json; print(json.load(open('$REPORT/SUMMARY.json')).get('fail',1))")
    FPASS=$(python3 -c "import json; print(json.load(open('$REPORT/SUMMARY.json')).get('pass',0))")
    ok "full workbench recorded pass=$FPASS fail=$FP"
    if [ "$EC" -eq 0 ] && [ "${FP:-1}" -eq 0 ]; then
      ok "full workbench WebView + API dual-assert"
    else
      bad "full workbench WebView e2e exit=$EC fail_lines=$FP (see full-workbench.log SUMMARY.json)"
    fi
  elif [ "$EC" -eq 0 ]; then
    ok "full workbench exit=0 (no SUMMARY.json)"
  else
    bad "full workbench exit=$EC (see full-workbench.log)"
  fi
fi
set -e

pkill -f "browboxs-desktop" 2>/dev/null || true
pkill -f "tauri-driver" 2>/dev/null || true
pkill -f "WebKitWebDriver" 2>/dev/null || true

finish
exit $?
