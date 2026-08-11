#!/usr/bin/env bash
# Post-install UI / function gate (S3) for public free runners.
# Thin wrapper around public-runner-product-smoke with explicit product intent:
#   - workbench UI depends on Local Agent API + static ui/desktop
#   - not "open browser console as product entry"
#   - optional desktop process under xvfb on Linux
#
# Usage (after real install root is ready):
#   bash scripts/public-runner-ui-function-smoke.sh /path/to/install-root
#
# Env: same as public-runner-product-smoke.sh
#   BROWBOX_SMOKE_SOFT=1           recommended on CI pack cells
#   BROWBOX_SMOKE_REQUIRE_DESKTOP=1 fail if desktop missing (full product)
#   BROWBOX_SMOKE_SKIP_UPDATE=0     exercise own-source update-check
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="${1:-${INSTALL_ROOT:-}}"
if [ -z "$INSTALL" ]; then
  echo "usage: $0 <install-root>" >&2
  exit 2
fi

SMOKE=""
for c in \
  "$ROOT/scripts/public-runner-product-smoke.sh" \
  "$(dirname "$0")/public-runner-product-smoke.sh"; do
  if [ -f "$c" ]; then SMOKE="$c"; break; fi
done
if [ -z "$SMOKE" ]; then
  echo "ERROR: public-runner-product-smoke.sh not found" >&2
  exit 2
fi

echo "== public-runner-ui-function-smoke (S3) =="
echo "  install-root=$INSTALL"
echo "  smoke=$SMOKE"
echo "  note: API matrix = workbench panels; desktop entry preferred over SERVE_UI"

export BROWBOX_SMOKE_SOFT="${BROWBOX_SMOKE_SOFT:-1}"
export BROWBOX_SMOKE_REQUIRE_DESKTOP="${BROWBOX_SMOKE_REQUIRE_DESKTOP:-0}"
export BROWBOX_SMOKE_SKIP_UPDATE="${BROWBOX_SMOKE_SKIP_UPDATE:-0}"

bash "$SMOKE" "$INSTALL"
ec=$?
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  if [ "$ec" -eq 0 ]; then
    echo "::notice title=ui-function-smoke::S3 UI/function gate OK root=$INSTALL"
  else
    echo "::warning title=ui-function-smoke::S3 exit=$ec (see smoke report)"
  fi
fi
exit "$ec"
