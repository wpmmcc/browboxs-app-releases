#!/usr/bin/env bash
# Security acceptance checks for a release stage or install root.
# Used by local smoke + CI after package-release / harden.
set -euo pipefail

ROOT="${1:-}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "usage: $0 <stage-or-install-root>" >&2
  exit 2
fi
ROOT="$(cd "$ROOT" && pwd)"
fail=0
ok() { echo "OK  $*"; }
bad() { echo "FAIL $*"; fail=1; }

echo "== package security check: $ROOT =="

# 1) required binaries
for b in browboxs-agent; do
  if [ -x "$ROOT/bin/$b" ] || [ -f "$ROOT/bin/${b}.exe" ]; then
    ok "binary $b present"
  else
    bad "missing $b"
  fi
done

# 2) SHA256SUMS
if [ -f "$ROOT/SHA256SUMS" ]; then
  ok "SHA256SUMS present"
  if [ -x "$(dirname "$0")/verify-package-integrity.sh" ]; then
    bash "$(dirname "$0")/verify-package-integrity.sh" "$ROOT" && ok "SHA256SUMS verify" || bad "SHA256SUMS verify"
  fi
else
  bad "SHA256SUMS missing (run secure-harden-release.sh)"
fi

# 3) no source maps / pdb
maps=$(find "$ROOT" \( -name '*.map' -o -name '*.pdb' \) 2>/dev/null | head -5 || true)
if [ -n "$maps" ]; then
  bad "debug maps present: $maps"
else
  ok "no .map/.pdb"
fi

# 4) binaries look stripped (Linux)
if command -v file >/dev/null 2>&1; then
  for b in "$ROOT/bin"/browboxs-agent "$ROOT/bin"/browboxs-server "$ROOT/bin"/browboxs-desktop; do
    [ -f "$b" ] || continue
    head -c 2 "$b" | grep -q '#!' && continue
    info=$(file "$b" || true)
    if echo "$info" | grep -qi 'not stripped'; then
      bad "not stripped: $b"
    else
      ok "stripped-or-ok $(basename "$b")"
    fi
  done
fi

# 5) no private key material in package text
if grep -RIlE 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|ghp_[A-Za-z0-9]{36}' \
  --exclude-dir=engines --exclude='*.tar.gz' --exclude='*.pak' \
  "$ROOT" 2>/dev/null | grep -vE 'docs/|SECURITY|SECURE' | head -5 | grep .; then
  bad "possible private material in package"
else
  ok "no private key patterns in text"
fi

# 6) secure report if present
if [ -f "$ROOT/SECURE-HARDEN-REPORT.txt" ]; then
  ok "SECURE-HARDEN-REPORT.txt"
  grep -q 'upx=disabled\|upx=enabled' "$ROOT/SECURE-HARDEN-REPORT.txt" && ok "upx policy recorded"
fi

# 7) product security: launch/install scripts must not ENABLE insecure flags
#    (exclude security check scripts themselves which mention the forbidden strings)
hits_insecure=$(
  grep -RInE '(^|[[:space:]])export[[:space:]]+BROWBOX_INSECURE_NO_AUTH=1|BROWBOX_INSECURE_NO_AUTH=1[[:space:]]*;' \
    "$ROOT/scripts" "$ROOT/bin" 2>/dev/null \
    | grep -vE 'verify-package-security|secure-harden|PRODUCT-SECURITY|SECURITY-RELEASE' \
    | head -5 || true
)
if [ -n "$hits_insecure" ]; then
  echo "$hits_insecure"
  bad "INSECURE_NO_AUTH enabled in package scripts (forbidden)"
else
  ok "no INSECURE_NO_AUTH enablement in package scripts"
fi
hits_serve=$(
  grep -RInE '(^|[[:space:]])export[[:space:]]+BROWBOX_SERVE_UI=1|BROWBOX_SERVE_UI=1[[:space:]]*;' \
    "$ROOT/scripts" "$ROOT/bin" 2>/dev/null \
    | grep -vE 'verify-package-security|secure-harden|PRODUCT-SECURITY|SECURITY-RELEASE' \
    | head -5 || true
)
if [ -n "$hits_serve" ]; then
  echo "$hits_serve"
  bad "BROWBOX_SERVE_UI=1 enabled in package (product forbids browser console)"
else
  ok "SERVE_UI not forced in package"
fi
# 8) INSTALL notes if present
if [ -f "$ROOT/INSTALL.txt" ]; then
  if grep -qiE 'desktop|工作台|Local API|不要.*浏览器' "$ROOT/INSTALL.txt"; then
    ok "INSTALL.txt mentions desktop / API guidance"
  else
    ok "INSTALL.txt present (consider security note)"
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "== RESULT: FAIL =="
  exit 1
fi
echo "== RESULT: PASS =="
