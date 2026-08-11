#!/usr/bin/env bash
# Linux x86_64 only: download install package (or use local path) → extract →
# product-smoke (function) + desktop-ui-e2e (UI form/nav).
# Intended for public free-runner cost probe + local validation.
#
# Usage:
#   bash scripts/run-linux-x86-install-ui-e2e.sh
#   bash scripts/run-linux-x86-install-ui-e2e.sh /path/to/browboxs-*-linux-x86_64.tar.gz
#   VERSION=0.2.4 bash scripts/run-linux-x86-install-ui-e2e.sh
#
# Env:
#   VERSION=0.2.4
#   APP_RELEASES_REPO=wpmmcc/browboxs-app-releases
#   BROWBOX_SMOKE_SOFT=0
#   BROWBOX_UI_E2E_STRICT=1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VER="${VERSION:-0.2.4}"
REPO="${APP_RELEASES_REPO:-wpmmcc/browboxs-app-releases}"
TAG="v${VER}"
ASSET="browboxs-${VER}-linux-x86_64.tar.gz"
WORK="${BROWBOX_E2E_WORK:-${TMPDIR:-/tmp}/bb-linux-x86-e2e-$$}"
mkdir -p "$WORK/dl" "$WORK/install" "$WORK/reports"
PKG="${1:-}"

echo "== linux-x86 install UI/function e2e =="
echo "  work=$WORK ver=$VER"

if [ -n "$PKG" ] && [ -f "$PKG" ]; then
  cp -f "$PKG" "$WORK/dl/$ASSET"
  echo "  using local package $PKG"
else
  if ! command -v gh >/dev/null; then
    echo "ERROR: gh required to download release, or pass local tar.gz" >&2
    exit 2
  fi
  echo "  download $TAG / $ASSET from $REPO"
  gh release download "$TAG" -R "$REPO" -p "$ASSET" -p "${ASSET}.sha256" -D "$WORK/dl" --clobber
fi

if [ -f "$WORK/dl/${ASSET}.sha256" ]; then
  (cd "$WORK/dl" && sha256sum -c "${ASSET}.sha256" || shasum -a 256 -c "${ASSET}.sha256")
fi

rm -rf "$WORK/stage" "$WORK/install"
mkdir -p "$WORK/stage" "$WORK/install"
tar -xzf "$WORK/dl/$ASSET" -C "$WORK/stage"
if [ -d "$WORK/stage/browboxs" ]; then SRC="$WORK/stage/browboxs"; else SRC="$WORK/stage"; fi
if command -v rsync >/dev/null; then rsync -a "$SRC/" "$WORK/install/"; else cp -a "$SRC/." "$WORK/install/"; fi
test -f "$WORK/install/bin/browboxs-agent"
test -f "$WORK/install/ui/desktop/index.html"
echo "  install-root=$WORK/install"

chmod +x scripts/*.sh 2>/dev/null || true
export BROWBOX_SMOKE_SOFT="${BROWBOX_SMOKE_SOFT:-0}"
export BROWBOX_SMOKE_PORT="${BROWBOX_SMOKE_PORT:-18991}"
export BROWBOX_SMOKE_REPORT="$WORK/reports/smoke"
export BROWBOX_UI_E2E_STRICT=1
export BROWBOX_UI_E2E_REQUIRE_DESKTOP=0
export BROWBOX_UI_E2E_PORT_AGENT=18992
export BROWBOX_UI_E2E_PORT_UI=18993
export BROWBOX_UI_E2E_REPORT="$WORK/reports/ui-e2e"
export BROWBOX_UI_E2E_HEADLESS="${BROWBOX_UI_E2E_HEADLESS:-0}"

echo
echo "== S3a product-smoke (function / package contract) =="
set +e
bash scripts/public-runner-product-smoke.sh "$WORK/install"
s1=$?
set -e
echo "product-smoke exit=$s1"

echo
echo "== S3b desktop-ui-e2e (nav + create form) =="
# Prefer scripts next to this file (public repo layout)
if [ -f scripts/public-runner-desktop-ui-e2e.sh ]; then
  set +e
  bash scripts/public-runner-desktop-ui-e2e.sh "$WORK/install"
  s2=$?
  set -e
else
  echo "ERROR: public-runner-desktop-ui-e2e.sh missing" >&2
  s2=2
fi
echo "ui-e2e exit=$s2"

echo
echo "== RESULT =="
echo "  smoke=$s1 ui-e2e=$s2"
echo "  reports: $WORK/reports"
if [ -f "$WORK/reports/ui-e2e/playwright/ui-e2e-report.json" ]; then
  python3 - <<PY
import json
r=json.load(open("$WORK/reports/ui-e2e/playwright/ui-e2e-report.json"))
print("  ui ok=", r.get("ok"), "errors=", r.get("errors"))
print("  profileId=", r.get("profileId"), "nav clicks=", sum(1 for c in r.get("clicks",[]) if c.get("ok")))
print("  forms=", [f.get("field") for f in r.get("forms",[])])
PY
fi

# billing note for public free
echo
echo "NOTE: this script is for local or single-cell public runner (linux-x86 only)."
echo "  Public standard runners are free/unlimited per GitHub docs; use this cell to"
echo "  observe billing UI if you only enable linux-x86 in pack-and-test."

[ "$s1" -eq 0 ] && [ "$s2" -eq 0 ]
exit $?
