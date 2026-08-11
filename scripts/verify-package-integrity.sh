#!/usr/bin/env bash
# Verify install package integrity via SHA256SUMS (and optional tarball .sha256).
# Exit 0 = ok, 1 = mismatch, 2 = missing checksums (soft if BROWBOX_INTEGRITY_SOFT=1).
set -euo pipefail

ROOT="${1:-${BROWBOX_INSTALL_ROOT:-}}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "usage: $0 <install-or-stage-root>" >&2
  exit 2
fi
ROOT="$(cd "$ROOT" && pwd)"
SUMS="$ROOT/SHA256SUMS"
SOFT="${BROWBOX_INTEGRITY_SOFT:-0}"

if [ ! -f "$SUMS" ]; then
  echo "WARN: no SHA256SUMS under $ROOT"
  if [ "$SOFT" = "1" ]; then
    exit 0
  fi
  exit 2
fi

echo "==> verifying $SUMS"
fail=0
checked=0
while read -r hash path; do
  [ -n "${hash:-}" ] || continue
  case "$hash" in \#*) continue ;; esac
  [ -n "${path:-}" ] || continue
  f="$ROOT/$path"
  if [ ! -f "$f" ]; then
    # path might already be absolute or relative differently
    f="$path"
  fi
  if [ ! -f "$f" ]; then
    echo "MISSING $path"
    fail=1
    continue
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$f" | awk '{print $1}')
  else
    got=$(shasum -a 256 "$f" | awk '{print $1}')
  fi
  exp=$(echo "$hash" | tr 'A-F' 'a-f')
  got=$(echo "$got" | tr 'A-F' 'a-f')
  checked=$((checked + 1))
  if [ "$got" != "$exp" ]; then
    echo "FAIL $path"
    echo "  expected $exp"
    echo "  got      $got"
    fail=1
  else
    echo "OK   $path"
  fi
done <"$SUMS"

echo "==> checked=$checked fail=$fail"
if [ "$checked" -eq 0 ]; then
  echo "WARN: SHA256SUMS empty"
  [ "$SOFT" = "1" ] && exit 0
  exit 2
fi
[ "$fail" -eq 0 ]
