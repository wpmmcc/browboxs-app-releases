#!/usr/bin/env bash
# S3b product UI gate: tauri-driver → OS WebView of **installed** browboxs-desktop.
# Not Playwright. Not python http.server + Chromium.
#
# Linux: hard fail (WebKitWebDriver + xvfb).
# Windows: run if msedgedriver+tauri-driver present; default soft.
# macOS: skip (no WKWebView native driver for tauri-driver).
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
if [ -z "$STRICT" ]; then
  case "$OS" in
    Linux*) STRICT=1 ;;
    *) STRICT=0 ;;
  esac
fi

PASS=0; FAIL=0; WARN=0
ok()   { PASS=$((PASS+1)); echo "PASS  $*"; echo "PASS  $*" >>"$REPORT/summary.txt"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL  $*"; echo "FAIL  $*" >>"$REPORT/summary.txt"; }
warn() { WARN=$((WARN+1)); echo "WARN  $*"; echo "WARN  $*" >>"$REPORT/summary.txt"; }

finish() {
  echo "== RESULT PASS=$PASS FAIL=$FAIL WARN=$WARN STRICT=$STRICT ==" | tee -a "$REPORT/summary.txt"
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
echo "  os=$OS strict=$STRICT"

case "$OS" in
  Darwin*)
    warn "macOS: tauri-driver has no WKWebView native driver — skip WebView e2e"
    echo "skip=macos-no-webkit-driver" >>"$REPORT/summary.txt"
    finish
    exit $?
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

export PATH="${HOME}/.cargo/bin:${PATH}"
if ! command -v tauri-driver >/dev/null 2>&1; then
  bad "tauri-driver not on PATH (install with cargo install tauri-driver)"
  finish
  exit $?
fi
ok "tauri-driver $(command -v tauri-driver)"

case "$OS" in
  Linux*)
    if ! command -v WebKitWebDriver >/dev/null 2>&1; then
      bad "WebKitWebDriver missing (apt install webkit2gtk-driver)"
      finish
      exit $?
    fi
    ok "WebKitWebDriver $(command -v WebKitWebDriver)"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    if ! command -v msedgedriver >/dev/null 2>&1 && [ ! -f ./msedgedriver.exe ]; then
      warn "msedgedriver not on PATH — Windows WebView e2e will likely fail"
    else
      ok "msedgedriver present"
    fi
    ;;
esac

E2E=""
for d in "$ROOT_SCRIPT/e2e-tauri" "$ROOT_SCRIPT/../e2e-tauri"; do
  if [ -f "$d/wdio.conf.js" ]; then E2E="$d"; break; fi
done
if [ -z "$E2E" ]; then
  bad "e2e-tauri/wdio.conf.js missing next to this script"
  finish
  exit $?
fi
ok "e2e-tauri dir $E2E"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  bad "node/npm required for WebdriverIO"
  finish
  exit $?
fi

pkill -f "browboxs-desktop" 2>/dev/null || true
pkill -f "tauri-driver" 2>/dev/null || true
pkill -f "WebKitWebDriver" 2>/dev/null || true
sleep 0.5

(
  cd "$E2E"
  if [ ! -d node_modules/@wdio/cli ]; then
    npm install --no-audit --no-fund
  fi
) >"$REPORT/npm.log" 2>&1 || {
  bad "npm install e2e-tauri failed (see npm.log)"
  finish
  exit $?
}

export BROWBOX_PREFIX="$INSTALL"
export BROWBOX_INSTALL_ROOT="$INSTALL"
export BROWBOX_DESKTOP="$DESKTOP"
export BROWBOX_AGENT_BIN="$AGENT"
export BROWBOX_TAURI_E2E_REPORT="$REPORT"
export BROWBOX_AGENT_PORT="${BROWBOX_AGENT_PORT:-18985}"
export BROWBOX_E2E_KEEP_SPLASH=1
export TAURI_DRIVER="$(command -v tauri-driver)"

run_wdio() {
  (cd "$E2E" && npx wdio run wdio.conf.js)
}

set +e
if [[ "$OS" == Linux* ]]; then
  if command -v xvfb-run >/dev/null 2>&1; then
    (cd "$E2E" && xvfb-run -a -s "-screen 0 1440x900x24" npx wdio run wdio.conf.js) \
      >"$REPORT/wdio.log" 2>&1
    EC=$?
  else
    bad "xvfb-run missing"
    finish
    exit $?
  fi
else
  run_wdio >"$REPORT/wdio.log" 2>&1
  EC=$?
fi
set -e

pkill -f "browboxs-desktop" 2>/dev/null || true
pkill -f "tauri-driver" 2>/dev/null || true
pkill -f "WebKitWebDriver" 2>/dev/null || true

tail -80 "$REPORT/wdio.log" || true

if [ "$EC" -eq 0 ]; then
  ok "tauri-driver WebView e2e (wdio exit=0)"
else
  bad "tauri-driver WebView e2e wdio exit=$EC (see wdio.log)"
fi

finish
exit $?
