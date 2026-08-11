#!/usr/bin/env bash
# S3 headed desktop / workbench UI e2e for PUBLIC free runners.
# Runs against an installed package root (bin + ui/desktop + scripts).
# No monorepo / no cargo.
#
# Linux: real Chromium window under xvfb (headed, not headless API-only).
# Windows/mac: headed Chromium when display available; soft-fail if browser install fails.
#
# Usage:
#   bash scripts/public-runner-desktop-ui-e2e.sh /path/to/install-root
#
# Env:
#   BROWBOX_UI_E2E_PORT_AGENT=18976
#   BROWBOX_UI_E2E_PORT_UI=18980
#   BROWBOX_UI_E2E_STRICT=0|1   fail job if e2e fails (default 1 on Linux, 0 elsewhere unless set)
#   BROWBOX_UI_E2E_REQUIRE_DESKTOP=0|1  also require desktop binary process (default 0)
#   BROWBOX_SMOKE_SOFT=1          if set, e2e failures become WARN
set -euo pipefail

ROOT_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
INSTALL="${1:-${INSTALL_ROOT:-}}"
if [ -z "$INSTALL" ]; then
  echo "usage: $0 <install-root>" >&2
  exit 2
fi
INSTALL="$(cd "$INSTALL" && pwd)"
REPORT="${BROWBOX_UI_E2E_REPORT:-${TMPDIR:-/tmp}/bb-ui-e2e-$$}"
mkdir -p "$REPORT"
AGENT_PORT="${BROWBOX_UI_E2E_PORT_AGENT:-18976}"
UI_PORT="${BROWBOX_UI_E2E_PORT_UI:-18980}"
SOFT="${BROWBOX_SMOKE_SOFT:-0}"
OS="$(uname -s 2>/dev/null || echo unknown)"
STRICT="${BROWBOX_UI_E2E_STRICT:-}"
if [ -z "$STRICT" ]; then
  case "$OS" in
    Linux*) STRICT=1 ;;
    *) STRICT=0 ;;
  esac
fi
REQ_DESKTOP="${BROWBOX_UI_E2E_REQUIRE_DESKTOP:-0}"

PASS=0; FAIL=0; WARN=0
ok()   { PASS=$((PASS+1)); echo "PASS  $*"; echo "PASS  $*" >>"$REPORT/summary.txt"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL  $*" >&2; echo "FAIL  $*" >>"$REPORT/summary.txt"; }
warn() { WARN=$((WARN+1)); echo "WARN  $*"; echo "WARN  $*" >>"$REPORT/summary.txt"; }
# Env soft (agent unrunnable / optional): WARN. Headed UI failures honor STRICT.
soft_bad() {
  if [ "$SOFT" = "1" ]; then warn "$@"; else bad "$@"; fi
}
fail_e2e() {
  if [ "$STRICT" = "1" ]; then bad "$@"; else warn "$@"; fi
}

echo "== public-runner-desktop-ui-e2e (S3 headed) =="
echo "  install=$INSTALL"
echo "  report=$REPORT"
echo "  os=$OS strict=$STRICT soft=$SOFT"

AGENT=""
for c in "$INSTALL/bin/browboxs-agent" "$INSTALL/bin/browboxs-agent.exe"; do
  [ -f "$c" ] && AGENT="$c" && break
done
DESKTOP=""
for c in "$INSTALL/bin/browboxs-desktop" "$INSTALL/bin/browboxs-desktop.exe"; do
  [ -f "$c" ] && DESKTOP="$c" && break
done
UI_DIR="$INSTALL/ui/desktop"
if [ -z "$AGENT" ]; then bad "agent binary missing"; echo "RESULT FAIL"; exit 1; fi
if [ ! -f "$UI_DIR/index.html" ]; then bad "ui/desktop/index.html missing"; echo "RESULT FAIL"; exit 1; fi
ok "agent + ui/desktop present"
if [ -n "$DESKTOP" ]; then ok "desktop binary present"
elif [ "$REQ_DESKTOP" = "1" ]; then bad "desktop binary required but missing"
else warn "desktop binary missing (slim kit) — still e2e workbench UI via Chromium+static"; fi

# ── start agent ──
export BROWBOX_AGENT_PORT="$AGENT_PORT"
export BROWBOX_AGENT_DATA="${BROWBOX_AGENT_DATA:-$REPORT/agent-data}"
export BROWBOX_INSTALL_ROOT="$INSTALL"
export BROWBOX_MODULES_MANIFEST="$INSTALL/modules/manifest.json"
export BROWBOX_ENGINES_DIR="${BROWBOX_ENGINES_DIR:-$INSTALL/engines}"
unset BROWBOX_SERVE_UI BROWBOX_INSECURE_NO_AUTH BROWBOX_UI_DIR || true
mkdir -p "$BROWBOX_AGENT_DATA"
(
  cd "$INSTALL"
  "$AGENT" >"$REPORT/agent.log" 2>&1 &
  echo $! >"$REPORT/agent.pid"
)
APID=$(cat "$REPORT/agent.pid")
cleanup() {
  kill "$APID" 2>/dev/null || true
  [ -n "${UIPID:-}" ] && kill "$UIPID" 2>/dev/null || true
  [ -n "${DPID:-}" ] && kill "$DPID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT

BASE="http://127.0.0.1:${AGENT_PORT}"
healthy=0
for _ in $(seq 1 60); do
  if curl -fsS "$BASE/v1/health" >"$REPORT/health.json" 2>/dev/null; then healthy=1; break; fi
  if ! kill -0 "$APID" 2>/dev/null; then break; fi
  sleep 0.25
done
if [ "$healthy" != "1" ]; then
  soft_bad "agent not healthy — skip headed UI e2e (see agent.log)"
  head -30 "$REPORT/agent.log" 2>/dev/null || true
  echo "== RESULT PASS=$PASS FAIL=$FAIL WARN=$WARN =="
  [ "$FAIL" -eq 0 ]
  exit $?
fi
ok "agent health"

TOKEN=""
for t in "$BROWBOX_AGENT_DATA/local_session.token" "$INSTALL/data/agent/local_session.token"; do
  if [ -f "$t" ]; then TOKEN=$(tr -d '\n\r' <"$t"); break; fi
done
if [ -z "$TOKEN" ]; then
  tpath=$(grep -oE 'path=[^ ]+local_session.token' "$REPORT/agent.log" 2>/dev/null | head -1 | cut -d= -f2- || true)
  [ -n "${tpath:-}" ] && [ -f "$tpath" ] && TOKEN=$(tr -d '\n\r' <"$tpath")
fi
[ -n "$TOKEN" ] && ok "session token" || warn "no session token — API create limited"

# ── static UI server (package ui/desktop) ──
if command -v python3 >/dev/null 2>&1; then
  (cd "$UI_DIR" && python3 -m http.server "$UI_PORT" --bind 127.0.0.1 >"$REPORT/ui-static.log" 2>&1) &
  UIPID=$!
elif command -v python >/dev/null 2>&1; then
  (cd "$UI_DIR" && python -m http.server "$UI_PORT" >"$REPORT/ui-static.log" 2>&1) &
  UIPID=$!
else
  soft_bad "python not available for static UI server"
  echo "== RESULT PASS=$PASS FAIL=$FAIL WARN=$WARN =="
  [ "$FAIL" -eq 0 ]; exit $?
fi
sleep 0.5
UI_URL="http://127.0.0.1:${UI_PORT}/"
ok "static UI server $UI_URL"

# ── optional: start desktop under xvfb (product shell process) ──
if [ -n "$DESKTOP" ] && [ "$OS" = "Linux" ] && command -v xvfb-run >/dev/null 2>&1; then
  set +e
  xvfb-run -a -s "-screen 0 1440x900x24" timeout 20 "$DESKTOP" >"$REPORT/desktop.log" 2>&1 &
  DPID=$!
  sleep 4
  if kill -0 "$DPID" 2>/dev/null; then
    ok "desktop process under xvfb (headed virtual display)"
  else
    wait "$DPID" 2>/dev/null
    warn "desktop exited early (webkitgtk may be missing) — see desktop.log"
    head -20 "$REPORT/desktop.log" 2>/dev/null || true
    DPID=""
  fi
  set -e
elif [ -n "$DESKTOP" ]; then
  warn "desktop present; process launch automation full path is Linux+xvfb (this OS: $OS)"
fi

# ── Playwright headed workbench clicks ──
E2E_DIR="$ROOT_SCRIPT/ui-e2e"
if [ ! -f "$E2E_DIR/workbench-playwright.mjs" ]; then
  soft_bad "missing $E2E_DIR/workbench-playwright.mjs"
  echo "== RESULT PASS=$PASS FAIL=$FAIL WARN=$WARN =="
  [ "$FAIL" -eq 0 ]; exit $?
fi

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  soft_bad "node/npm required for Playwright UI e2e"
  echo "== RESULT PASS=$PASS FAIL=$FAIL WARN=$WARN =="
  [ "$FAIL" -eq 0 ]; exit $?
fi

echo "== npm install playwright (ui-e2e) =="
(
  cd "$E2E_DIR"
  if [ ! -d node_modules/playwright ]; then
    npm install --no-audit --no-fund --silent 2>"$REPORT/npm-install.err" || npm install --no-audit --no-fund
  fi
  # browser binary
  npx playwright install chromium 2>"$REPORT/pw-install.log" || true
) || soft_bad "playwright install failed"

export BROWBOX_UI_E2E_TOKEN="$TOKEN"
export BROWBOX_UI_E2E_HEADLESS=0
# Linux: headed Chromium under xvfb (virtual display — free runners have no physical monitor)
set +e
if [ "$OS" = "Linux" ] && command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a -s "-screen 0 1440x900x24" \
    env BROWBOX_UI_E2E_TOKEN="$TOKEN" BROWBOX_UI_E2E_HEADLESS=0 \
    node "$E2E_DIR/workbench-playwright.mjs" \
      --url "$UI_URL" --agent "$BASE" --out "$REPORT/playwright" \
      >"$REPORT/pw-run.out" 2>"$REPORT/pw-run.err"
  pec=$?
else
  env BROWBOX_UI_E2E_TOKEN="$TOKEN" BROWBOX_UI_E2E_HEADLESS=0 \
    node "$E2E_DIR/workbench-playwright.mjs" \
      --url "$UI_URL" --agent "$BASE" --out "$REPORT/playwright" \
      >"$REPORT/pw-run.out" 2>"$REPORT/pw-run.err"
  pec=$?
fi
set -e

if [ "$pec" -eq 0 ]; then
  ok "Playwright headed workbench UI e2e"
else
  fail_e2e "Playwright headed UI e2e exit=$pec (see $REPORT/playwright $REPORT/pw-run.err)"
  tail -40 "$REPORT/pw-run.err" 2>/dev/null || true
  tail -20 "$REPORT/pw-run.out" 2>/dev/null || true
fi

if [ -f "$REPORT/playwright/ui-e2e-report.json" ]; then
  ok "ui-e2e-report.json written"
  # show click summary
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<PY
import json
r=json.load(open("$REPORT/playwright/ui-e2e-report.json"))
print("clicks_ok", sum(1 for c in r.get("clicks",[]) if c.get("ok")), "errors", r.get("errors"))
PY
  fi
fi

echo
echo "== RESULT PASS=$PASS FAIL=$FAIL WARN=$WARN =="
echo "report: $REPORT"
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::notice title=desktop-ui-e2e::PASS=$PASS FAIL=$FAIL WARN=$WARN"
  [ "$FAIL" -gt 0 ] && echo "::error title=desktop-ui-e2e::FAIL=$FAIL"
fi
[ "$FAIL" -eq 0 ]
exit $?
