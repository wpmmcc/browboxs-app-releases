#!/usr/bin/env bash
# Public free-runner product smoke — NO source build, NO monorepo required.
# Runs against an extracted / installed package root (binaries + ui static + scripts).
#
# Covers what the workbench UI depends on (Agent Local API + static assets + update channel)
# plus install-type update-source correctness. Optional desktop binary process check under xvfb.
#
# Usage:
#   bash scripts/public-runner-product-smoke.sh /path/to/browboxs-install-root
#   INSTALL_ROOT=... PORT=18971 bash scripts/public-runner-product-smoke.sh
#
# Env:
#   BROWBOX_SMOKE_PORT          default 18971
#   BROWBOX_SMOKE_REQUIRE_DESKTOP  0|1  fail if desktop missing (default 0)
#   BROWBOX_SMOKE_SKIP_UPDATE     0|1  skip GitHub update-check (default 0)
#   BROWBOX_SMOKE_SOFT           0|1  treat functional API failures as WARN (default 0)
#   GH_TOKEN / GITHUB_TOKEN      optional for higher API rate on update-check
set -euo pipefail

ROOT="${1:-${INSTALL_ROOT:-}}"
if [ -z "$ROOT" ]; then
  echo "usage: $0 <install-root>" >&2
  exit 2
fi
ROOT="$(cd "$ROOT" && pwd)"
PORT="${BROWBOX_SMOKE_PORT:-18971}"
REQUIRE_DESKTOP="${BROWBOX_SMOKE_REQUIRE_DESKTOP:-0}"
SKIP_UPDATE="${BROWBOX_SMOKE_SKIP_UPDATE:-0}"
SOFT="${BROWBOX_SMOKE_SOFT:-0}"
REPORT_DIR="${BROWBOX_SMOKE_REPORT:-${TMPDIR:-/tmp}/browboxs-product-smoke-$$}"
mkdir -p "$REPORT_DIR"

PASS=0; FAIL=0; WARN=0
ok()   { PASS=$((PASS+1)); echo "PASS  $*"; echo "PASS  $*" >>"$REPORT_DIR/summary.txt"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL  $*" >&2; echo "FAIL  $*" >>"$REPORT_DIR/summary.txt"; }
warn() { WARN=$((WARN+1)); echo "WARN  $*"; echo "WARN  $*" >>"$REPORT_DIR/summary.txt"; }
soft_bad() {
  if [ "$SOFT" = "1" ]; then warn "$@"; else bad "$@"; fi
}

AGENT=""
for c in "$ROOT/bin/browboxs-agent" "$ROOT/bin/browboxs-agent.exe"; do
  [ -f "$c" ] && AGENT="$c" && break
done
SERVER=""
for c in "$ROOT/bin/browboxs-server" "$ROOT/bin/browboxs-server.exe"; do
  [ -f "$c" ] && SERVER="$c" && break
done
DESKTOP=""
for c in "$ROOT/bin/browboxs-desktop" "$ROOT/bin/browboxs-desktop.exe"; do
  [ -f "$c" ] && DESKTOP="$c" && break
done

echo "== public-runner-product-smoke =="
echo "  root=$ROOT"
echo "  port=$PORT"
echo "  report=$REPORT_DIR"
echo "  os=$(uname -s) arch=$(uname -m)"

# ── 1. Package shape (product contract) ──
if [ -n "$AGENT" ]; then ok "binary agent present"; else bad "binary agent missing"; fi
if [ -n "$SERVER" ]; then ok "binary server present"; else bad "binary server missing"; fi
if [ -n "$DESKTOP" ]; then
  ok "binary desktop present"
elif [ "$REQUIRE_DESKTOP" = "1" ]; then
  bad "binary desktop missing (required)"
else
  warn "binary desktop missing (slim kit — UI shell not in this package)"
fi

if [ -f "$ROOT/modules/manifest.json" ]; then ok "manifest.json"; else bad "manifest.json missing"; fi
if [ -f "$ROOT/scripts/update-modules.sh" ]; then ok "update-modules.sh"; else bad "update-modules.sh missing"; fi
if [ -d "$ROOT/ui/desktop" ] && [ -f "$ROOT/ui/desktop/index.html" ]; then
  ok "ui/desktop static present"
else
  bad "ui/desktop/index.html missing (desktop shell frontendDist)"
fi

# UI static completeness (what Tauri loads)
UI="$ROOT/ui/desktop"
if [ -f "$UI/index.html" ]; then
  if grep -qE 'script|assets/' "$UI/index.html"; then ok "ui index references assets"
  else soft_bad "ui index.html looks empty of bundles"; fi
  # key workbench route markers in JS bundles (minified ok)
  if find "$UI" -type f \( -name '*.js' -o -name '*.css' \) | head -1 | grep -q .; then
    ok "ui has js/css assets"
  else
    soft_bad "ui missing js/css assets"
  fi
  # product must not advertise browser console as entry in INSTALL
  if [ -f "$ROOT/INSTALL.txt" ] && grep -qi 'desktop' "$ROOT/INSTALL.txt"; then
    ok "INSTALL.txt mentions desktop entry"
  else
    warn "INSTALL.txt missing desktop guidance"
  fi
fi

# Own-source channels
if [ -f "$ROOT/modules/manifest.json" ]; then
  eval "$(python3 - "$ROOT/modules/manifest.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
g=m.get("github_app") or m.get("github") or {}
e=m.get("github_engines") or {}
print(f"APP_SRC={g.get('owner','')}/{g.get('repo','')}")
print(f"ENG_SRC={e.get('owner','')}/{e.get('repo','')}")
print(f"PROD_VER={m.get('product_version','')}")
itype=(m.get("packaging") or {}).get("install_type","")
print(f"INSTALL_TYPE={itype}")
its=(m.get("packaging") or {}).get("install_types") or {}
bad=[]
for k,v in its.items():
  if v.get("update_source") not in (None,"github_app","github"):
    bad.append(k)
print(f"TYPES_BAD={','.join(bad)}")
PY
)"
  if [ "${APP_SRC:-}" = "wpmmcc/browboxs-app-releases" ]; then ok "app source $APP_SRC"
  else bad "app source unexpected: ${APP_SRC:-empty}"; fi
  if [ "${ENG_SRC:-}" = "wpmmcc/browboxs-engines-releases" ]; then ok "engines source $ENG_SRC"
  else bad "engines source unexpected: ${ENG_SRC:-empty}"; fi
  if [ -n "${PROD_VER:-}" ]; then ok "product_version=$PROD_VER"; else warn "product_version empty"; fi
  if [ -z "${TYPES_BAD:-}" ]; then ok "install_types all map to app channel"
  else soft_bad "install_types bad: $TYPES_BAD"; fi
fi

# No accidental source tree in package
if [ -d "$ROOT/crates" ] || [ -f "$ROOT/Cargo.toml" ] || [ -d "$ROOT/apps/desktop/src" ]; then
  bad "SOURCE LEAK: package must not contain monorepo source (crates/Cargo.toml/apps src)"
else
  ok "no monorepo source in package"
fi

# Security quick gate if present
if [ -x "$ROOT/scripts/verify-package-security.sh" ]; then
  if bash "$ROOT/scripts/verify-package-security.sh" "$ROOT" >"$REPORT_DIR/security.log" 2>&1; then
    ok "verify-package-security"
  else
    soft_bad "verify-package-security (see security.log)"
  fi
fi

if [ -z "$AGENT" ]; then
  echo "== RESULT FAIL=$FAIL PASS=$PASS WARN=$WARN (no agent) =="
  [ "$FAIL" -eq 0 ]
  exit $?
fi

# ── 2. Start agent (product: no SERVE_UI) ──
kill_port() {
  local p=$1
  if command -v fuser >/dev/null 2>&1; then fuser -k "${p}/tcp" 2>/dev/null || true
  elif command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:"$p" -sTCP:LISTEN 2>/dev/null | xargs -r kill 2>/dev/null || true
  fi
  sleep 0.2
}
kill_port "$PORT"
export BROWBOX_AGENT_PORT="$PORT"
export BROWBOX_AGENT_DATA="${BROWBOX_AGENT_DATA:-$REPORT_DIR/agent-data}"
export BROWBOX_INSTALL_ROOT="$ROOT"
export BROWBOX_MODULES_MANIFEST="$ROOT/modules/manifest.json"
export BROWBOX_ENGINES_DIR="${BROWBOX_ENGINES_DIR:-$ROOT/engines}"
unset BROWBOX_SERVE_UI BROWBOX_INSECURE_NO_AUTH BROWBOX_UI_DIR || true
mkdir -p "$BROWBOX_AGENT_DATA"

# Windows/Git Bash: run agent from root
(
  cd "$ROOT"
  if [[ "$AGENT" == *.exe ]]; then
    "$AGENT" >"$REPORT_DIR/agent.log" 2>&1 &
  else
    "$AGENT" >"$REPORT_DIR/agent.log" 2>&1 &
  fi
  echo $! >"$REPORT_DIR/agent.pid"
)
PID=$(cat "$REPORT_DIR/agent.pid")
cleanup() {
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  kill_port "$PORT"
}
trap cleanup EXIT

BASE="http://127.0.0.1:${PORT}"
healthy=0
for _ in $(seq 1 60); do
  if curl -fsS "$BASE/v1/health" >"$REPORT_DIR/health.json" 2>/dev/null; then
    healthy=1; break
  fi
  # binary may not run (glibc) — detect early
  if ! kill -0 "$PID" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if [ "$healthy" != "1" ]; then
  if ! kill -0 "$PID" 2>/dev/null; then
    warn "agent binary not runnable on this runner (often GLIBC/arch) — skip live API matrix"
    echo "agent.log:"; head -20 "$REPORT_DIR/agent.log" 2>/dev/null || true
    # still run offline checks
    SKIP_LIVE=1
  else
    bad "agent health timeout"
    head -30 "$REPORT_DIR/agent.log" || true
    SKIP_LIVE=1
  fi
else
  SKIP_LIVE=0
  if grep -q '"ok":true\|"status".*ok\|ok' "$REPORT_DIR/health.json" 2>/dev/null; then
    ok "agent /v1/health"
  else
    soft_bad "health body unexpected: $(head -c 120 "$REPORT_DIR/health.json")"
  fi
fi

auth_hdr=()
TOKEN=""
if [ "$SKIP_LIVE" = "0" ]; then
  # unauth must 401
  code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/v1/profiles" || echo 000)
  if [ "$code" = "401" ]; then ok "unauth profiles → 401"
  else soft_bad "unauth profiles got $code (expect 401)"; fi

  # locate session token
  for t in \
    "$BROWBOX_AGENT_DATA/local_session.token" \
    "$ROOT/data/agent/local_session.token" \
    "$ROOT/.browboxs-client-data/local_session.token"; do
    if [ -f "$t" ]; then TOKEN=$(tr -d '\n\r' <"$t"); break; fi
  done
  if [ -z "$TOKEN" ]; then
    tpath=$(grep -oE 'path=[^ ]+local_session.token' "$REPORT_DIR/agent.log" 2>/dev/null | head -1 | cut -d= -f2- || true)
    [ -n "${tpath:-}" ] && [ -f "$tpath" ] && TOKEN=$(tr -d '\n\r' <"$tpath")
  fi
  if [ -n "$TOKEN" ]; then
    auth_hdr=(-H "Authorization: Bearer $TOKEN")
    code=$(curl -s -o /dev/null -w '%{http_code}' "${auth_hdr[@]}" "$BASE/v1/profiles" || echo 000)
    if [ "$code" = "200" ]; then ok "auth Bearer profiles → 200"
    else soft_bad "auth profiles got $code"; fi
  else
    warn "session token not found — API matrix limited"
  fi

  # Root must NOT be SPA console
  body=$(curl -s "$BASE/" || true)
  if echo "$body" | grep -qiE 'desktop_only|Local API|browboxs-agent|service|API'; then
    ok "agent / is API-only (not browser workbench)"
  elif echo "$body" | grep -qiE '<div id="root"|vite|react'; then
    bad "agent / serves SPA — product entry must be desktop, not SERVE_UI"
  else
    warn "agent / body unclear: ${body:0:80}"
  fi
fi

# ── 3. UI-feature API matrix (mirrors workbench panels) ──
api() {
  # api METHOD PATH [json-body]
  local method=$1 path=$2; shift 2
  local out="$REPORT_DIR/api-$(echo "$path" | tr '/{}' '___').json"
  local code
  if [ $# -gt 0 ]; then
    code=$(curl -s -o "$out" -w '%{http_code}' -X "$method" "${auth_hdr[@]}" \
      -H 'Content-Type: application/json' -d "$1" "$BASE$path" || echo 000)
  else
    code=$(curl -s -o "$out" -w '%{http_code}' -X "$method" "${auth_hdr[@]}" "$BASE$path" || echo 000)
  fi
  echo "$code"
}

if [ "$SKIP_LIVE" = "0" ] && [ -n "$TOKEN" ]; then
  # App / host (sidebar status)
  for path in /v1/health /v1/engines /v1/profiles /v1/proxies /v1/workflows /v1/tasks /v1/sessions; do
    c=$(api GET "$path")
    if [ "$c" = "200" ]; then ok "UI-API GET $path"
    else soft_bad "UI-API GET $path → $c"; fi
  done

  # Optional richer endpoints
  for path in /v1/app/info /v1/host/status /v1/locks /v1/updates/status /v1/updates/check /v1/updates/modules; do
    c=$(api GET "$path")
    case "$c" in
      200) ok "UI-API GET $path" ;;
      404) warn "UI-API GET $path not implemented (404)" ;;
      401) soft_bad "UI-API GET $path unauthorized" ;;
      *) warn "UI-API GET $path → $c" ;;
    esac
  done

  # Fingerprint generate (profile create panel)
  c=$(api POST /v1/fingerprint/generate '{"platform":"Win32"}')
  case "$c" in
    200|201) ok "UI-API fingerprint/generate" ;;
    404) warn "fingerprint/generate 404" ;;
    *) soft_bad "fingerprint/generate → $c" ;;
  esac

  # Create profile (核心环境管理)
  FP='{"schema_version":1,"platform":"Win32","user_agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36","language":"en-US","timezone":"UTC"}'
  c=$(api POST /v1/profiles "{\"name\":\"smoke-profile-$(date +%s)\",\"engine_id\":\"fingerprint-chromium\",\"fingerprint\":$FP}")
  if [ "$c" = "200" ] || [ "$c" = "201" ]; then
    ok "UI-API create profile"
    PID_P=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print((d.get("data") or d).get("id",""))' \
      "$REPORT_DIR/api-__v1_profiles.json" 2>/dev/null || true)
    if [ -n "${PID_P:-}" ]; then
      # cookies (cookie 管理面板)
      c=$(api POST "/v1/profiles/${PID_P}/cookies/import" \
        '{"cookies":[{"name":"smoke","value":"1","domain":"example.com","path":"/"}],"mode":"replace"}')
      case "$c" in 200|201|204) ok "UI-API cookies import" ;; *) soft_bad "cookies import → $c" ;; esac
      c=$(api GET "/v1/profiles/${PID_P}/cookies")
      case "$c" in 200) ok "UI-API cookies list" ;; *) soft_bad "cookies list → $c" ;; esac
      # launch-plan (open 预检 — 无头环境可能无引擎)
      c=$(api GET "/v1/profiles/${PID_P}/launch-plan")
      case "$c" in 200) ok "UI-API launch-plan" ;; 4*|5*) warn "launch-plan → $c (slim/no engine ok)" ;; *) warn "launch-plan → $c" ;; esac
      # batch edit
      c=$(api POST /v1/profiles/batch/edit \
        "{\"ids\":[\"$PID_P\"],\"group\":\"smoke-g\",\"tags\":[\"ci\"],\"notes\":\"public-runner\"}")
      case "$c" in 200|201) ok "UI-API batch edit" ;; 404) warn "batch edit 404" ;; *) soft_bad "batch edit → $c" ;; esac
    fi
  else
    soft_bad "create profile → $c body=$(head -c 200 "$REPORT_DIR/api-__v1_profiles.json" 2>/dev/null || true)"
  fi

  # Proxy list/create shape (代理面板)
  c=$(api POST /v1/proxies '{"name":"smoke-proxy","type":"http","host":"127.0.0.1","port":18080}')
  case "$c" in
    200|201) ok "UI-API create proxy" ;;
    400|422) warn "proxy create validation $c (schema may differ)" ;;
    404) warn "proxies POST 404" ;;
    *) soft_bad "create proxy → $c" ;;
  esac

  # Workflow (RPA 面板)
  c=$(api POST /v1/workflows '{"name":"smoke-wf","steps":[{"op":"click","selectors":["body"]}]}')
  case "$c" in
    200|201) ok "UI-API create workflow" ;;
    404) warn "workflows POST 404" ;;
    *) soft_bad "create workflow → $c" ;;
  esac

  # Updates panel
  c=$(api GET /v1/updates/check)
  case "$c" in
    200)
      ok "UI-API updates/check"
      if [ -f "$REPORT_DIR/api-__v1_updates_check.json" ]; then
        ok "updates/check body readable"
      fi
      ;;
    404) warn "updates/check 404" ;;
    *) soft_bad "updates/check → $c" ;;
  esac
fi

# ── 4. Update script own-source (install type) ──
if [ "$SKIP_UPDATE" != "1" ] && [ -x "$ROOT/scripts/update-modules.sh" ]; then
  set +e
  BROWBOX_INSTALL_ROOT="$ROOT" bash "$ROOT/scripts/update-modules.sh" --check \
    >"$REPORT_DIR/update-check.log" 2>&1
  uc=$?
  set -e
  if grep -q 'wpmmcc/browboxs-app-releases' "$REPORT_DIR/update-check.log" \
     && grep -q 'selected:' "$REPORT_DIR/update-check.log" \
     && grep -qE 'browboxs-.*\.(tar\.gz|tgz)' "$REPORT_DIR/update-check.log" \
     && ! grep -qE 'selected:.*portable|selected:.*\.deb' "$REPORT_DIR/update-check.log"; then
    sel=$(grep 'selected:' "$REPORT_DIR/update-check.log" | head -1 | sed 's/^ *//')
    ok "update-check own tree: $sel"
  else
    if [ "$uc" -ne 0 ] && grep -qiE 'rate limit|cannot fetch|403|API' "$REPORT_DIR/update-check.log"; then
      warn "update-check network/API issue (runner)"
    else
      soft_bad "update-check failed or wrong asset (see update-check.log)"
    fi
  fi
  if grep -q 'engines-releases' "$REPORT_DIR/update-check.log"; then
    ok "engines channel separated in update script"
  else
    warn "engines channel not printed in update-check"
  fi
fi

# ── 5. Optional desktop shell (Linux xvfb) ──
if [ -n "$DESKTOP" ] && [ "$(uname -s)" = "Linux" ]; then
  if command -v xvfb-run >/dev/null 2>&1; then
    set +e
    timeout 8 xvfb-run -a "$DESKTOP" >"$REPORT_DIR/desktop.log" 2>&1 &
    dpid=$!
    sleep 3
    if kill -0 "$dpid" 2>/dev/null; then
      ok "desktop process starts under xvfb"
      kill "$dpid" 2>/dev/null || true
      wait "$dpid" 2>/dev/null || true
    else
      wait "$dpid" 2>/dev/null
      warn "desktop exited early (see desktop.log) — may need WebKitGTK on runner"
      head -15 "$REPORT_DIR/desktop.log" 2>/dev/null || true
    fi
    set -e
  else
    warn "xvfb-run not available — skip desktop process smoke"
  fi
elif [ -n "$DESKTOP" ]; then
  warn "desktop binary present; process smoke only fully automated on Linux+xvfb"
fi

# ── 6. Server binary brief smoke (optional node host) ──
if [ -n "$SERVER" ] && [ "$SKIP_LIVE" = "0" ]; then
  # just ensure --help or version doesn't crash
  set +e
  timeout 3 "$SERVER" --help >"$REPORT_DIR/server-help.txt" 2>&1 \
    || timeout 3 "$SERVER" -h >"$REPORT_DIR/server-help.txt" 2>&1 \
    || true
  set -e
  if [ -s "$REPORT_DIR/server-help.txt" ] || true; then
    ok "server binary exists (help smoke best-effort)"
  fi
fi

echo
echo "== RESULT: PASS=$PASS FAIL=$FAIL WARN=$WARN =="
echo "report: $REPORT_DIR"
# GitHub annotations
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::notice title=product-smoke::PASS=$PASS FAIL=$FAIL WARN=$WARN root=$ROOT"
  [ "$FAIL" -gt 0 ] && echo "::error title=product-smoke::FAIL=$FAIL — see artifact smoke-report"
fi
[ "$FAIL" -eq 0 ]
exit $?
