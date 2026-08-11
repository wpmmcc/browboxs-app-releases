#!/usr/bin/env bash
# Public-side pack: consume a source-free kit → user release tarball.
# Does NOT cargo-build core crates. Safe for free public runners.
#
# Usage:
#   bash scripts/pack-kit-to-release.sh
#   KIT=dist/kits/kit-linux-x86_64.tar.gz bash scripts/pack-kit-to-release.sh
#   bash scripts/pack-kit-to-release.sh --kit /path/to/kit-linux-x86_64.tar.gz --version 0.1.0
#
# Output (see docs/PACKAGING-TYPES-AND-COMPAT.md):
#   dist/release-assets/browboxs-<ver>-<os>-<arch>.tar.gz   (tree — always)
#   …-portable.zip  when BROWBOX_PACK_KINDS contains portable
#   deb/AppImage/nsis/dmg when tools + kinds allow (best-effort on runner)
#   RELEASE-SHA256SUMS.txt
#
# Env BROWBOX_PACK_KINDS: comma list tree,portable,deb,appimage,rpm,nsis,msi,dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# When mirrored into public app-releases, ROOT may be that repo root
if [ -f "$ROOT/scripts/pack-kit-to-release.sh" ]; then
  :
elif [ -f "$ROOT/pack-kit-to-release.sh" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)/.."
fi
cd "$ROOT"

VER="${BROWBOX_VERSION:-}"
KIT="${KIT:-}"
OUT_DIR="${OUT_DIR:-$ROOT/dist/release-assets}"
ALLOW_MISSING_DESKTOP="${ALLOW_MISSING_DESKTOP:-1}"
RUN_SMOKE="${RUN_SMOKE:-1}"
RUN_SECURITY="${RUN_SECURITY:-1}"
PACK_KINDS="${BROWBOX_PACK_KINDS:-tree}"

while [ $# -gt 0 ]; do
  case "$1" in
    --kit) KIT="$2"; shift 2 ;;
    --version) VER="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --kinds) PACK_KINDS="$2"; shift 2 ;;
    --no-smoke) RUN_SMOKE=0; shift ;;
    --no-security) RUN_SECURITY=0; shift ;;
    -h|--help)
      sed -n '1,30p' "$0"
      exit 0
      ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done

kind_has() {
  echo ",${PACK_KINDS}," | grep -q ",$1,"
}

sha_file() {
  local f="$1" base
  base=$(basename "$f")
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "$f")" && sha256sum "$base" >"${base}.sha256")
    awk '{print $1}' "${f}.sha256"
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$(dirname "$f")" && shasum -a 256 "$base" >"${base}.sha256")
    awk '{print $1}' "${f}.sha256"
  else
    echo "unknown"
  fi
}

append_sum() {
  local sum="$1" asset="$2"
  local SUMS="$OUT_DIR/RELEASE-SHA256SUMS.txt"
  {
    echo "# browboxs release assets"
    [ -f "$SUMS" ] && grep -v "^#" "$SUMS" | grep -v "  ${asset}$" || true
    echo "${sum}  ${asset}"
  } >"${SUMS}.tmp"
  mv "${SUMS}.tmp" "$SUMS"
}

if [ -z "$KIT" ]; then
  # Prefer host platform kit
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  case "$ARCH" in x86_64|amd64) ARCH=x86_64 ;; aarch64|arm64) ARCH=aarch64 ;; esac
  case "$OS" in msys*|mingw*|cygwin*) OS=windows ;; darwin) OS=darwin ;; linux) OS=linux ;; esac
  for cand in \
    "$ROOT/dist/kits/kit-${OS}-${ARCH}.tar.gz" \
    "$ROOT/kit-${OS}-${ARCH}.tar.gz" \
    $(ls "$ROOT"/dist/kits/kit-*.tar.gz 2>/dev/null | head -1) \
    $(ls "$ROOT"/kit-*.tar.gz 2>/dev/null | head -1); do
    if [ -n "${cand:-}" ] && [ -f "$cand" ]; then KIT="$cand"; break; fi
  done
fi

if [ -z "$KIT" ] || [ ! -f "$KIT" ]; then
  echo "ERROR: kit tarball not found. Set KIT= or run make-kit first." >&2
  exit 1
fi
KIT="$(cd "$(dirname "$KIT")" && pwd)/$(basename "$KIT")"

# Verify sidecar sha256 if present
if [ -f "${KIT}.sha256" ]; then
  echo "== verify kit sha256 =="
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "$KIT")" && sha256sum -c "$(basename "$KIT").sha256")
  elif command -v shasum >/dev/null 2>&1; then
    expect=$(awk '{print $1}' "${KIT}.sha256")
    got=$(shasum -a 256 "$KIT" | awk '{print $1}')
    [ "$expect" = "$got" ] || { echo "SHA256 mismatch"; exit 1; }
    echo "OK sha256"
  fi
fi

WORK="${TMPDIR:-/tmp}/browboxs-pack-$$"
rm -rf "$WORK"
mkdir -p "$WORK"
tar -xzf "$KIT" -C "$WORK"

# kit layout: PLATFORM.txt VERSION TRIPLE.txt HARDENING.txt browboxs/
PLAT_FILE="$WORK/PLATFORM.txt"
VER_FILE="$WORK/VERSION"
test -f "$PLAT_FILE"
test -d "$WORK/browboxs"
PLATFORM=$(tr -d ' \n\r' <"$PLAT_FILE")
if [ -z "$VER" ]; then
  if [ -f "$VER_FILE" ]; then VER=$(tr -d ' \n\r' <"$VER_FILE"); else VER=0.1.0; fi
fi

# platform key for asset names: linux-x86_64 | windows-x86_64 | macos-aarch64 (user-facing)
# kits use darwin; release assets may use macos per PACKAGING §4
case "$PLATFORM" in
  darwin-*) OS_ARCH="macos-${PLATFORM#darwin-}" ;;
  *) OS_ARCH="$PLATFORM" ;;
esac
# also keep linux-*/windows-* as-is
case "$PLATFORM" in
  linux-*|windows-*) OS_ARCH="$PLATFORM" ;;
esac

STAGE="$WORK/browboxs"
test -f "$STAGE/bin/browboxs-agent" -o -f "$STAGE/bin/browboxs-agent.exe"

# Ensure launchers do not force SERVE_UI
if [ -f "$STAGE/bin/browboxs-start-agent" ]; then
  if grep -q 'BROWBOX_SERVE_UI=1' "$STAGE/bin/browboxs-start-agent" 2>/dev/null; then
    echo "ERROR: kit launcher forces SERVE_UI=1" >&2
    exit 1
  fi
fi

# Re-run security gate if scripts present
SEC_SCRIPT=""
for s in \
  "$STAGE/scripts/verify-package-security.sh" \
  "$ROOT/scripts/verify-package-security.sh" \
  "$ROOT/verify-package-security.sh"; do
  [ -f "$s" ] && SEC_SCRIPT="$s" && break
done
if [ "$RUN_SECURITY" = "1" ] && [ -n "$SEC_SCRIPT" ]; then
  echo "== verify-package-security =="
  bash "$SEC_SCRIPT" "$STAGE"
fi

if [ "$ALLOW_MISSING_DESKTOP" != "1" ]; then
  if [ ! -f "$STAGE/bin/browboxs-desktop" ] && [ ! -f "$STAGE/bin/browboxs-desktop.exe" ]; then
    echo "ERROR: browboxs-desktop missing (ALLOW_MISSING_DESKTOP=0)" >&2
    exit 1
  fi
fi

# Desktop entry note in package
if [ ! -f "$STAGE/INSTALL.txt" ]; then
  cat >"$STAGE/INSTALL.txt" <<EOF
Product entry: bin/browboxs-desktop (not browser on Local API port).
EOF
fi

mkdir -p "$OUT_DIR"
echo "== pack kinds: $PACK_KINDS =="

# Always produce install tree tar (热更新 / 通用)
ASSET="browboxs-${VER}-${OS_ARCH}.tar.gz"
OUT_TAR="$OUT_DIR/$ASSET"
tar -C "$WORK" -czf "$OUT_TAR" browboxs
SUM=$(sha_file "$OUT_TAR")
append_sum "$SUM" "$ASSET"
echo "PACK OK tree: $OUT_TAR sha256=$SUM"

# Portable zip (Windows-oriented; also useful on any OS)
if kind_has portable; then
  PORT="browboxs-${VER}-${OS_ARCH}-portable.zip"
  if command -v zip >/dev/null 2>&1; then
    (cd "$WORK" && zip -qr "$OUT_DIR/$PORT" browboxs)
    PSUM=$(sha_file "$OUT_DIR/$PORT")
    append_sum "$PSUM" "$PORT"
    echo "PACK OK portable: $OUT_DIR/$PORT"
  else
    # fallback: copy tar as portable-named (document as tar portable)
    cp -f "$OUT_TAR" "$OUT_DIR/browboxs-${VER}-${OS_ARCH}-portable.tar.gz"
    PSUM=$(sha_file "$OUT_DIR/browboxs-${VER}-${OS_ARCH}-portable.tar.gz")
    append_sum "$PSUM" "browboxs-${VER}-${OS_ARCH}-portable.tar.gz"
    echo "PACK OK portable(tar fallback): zip not installed"
  fi
fi

# Optional native installers when artifacts already in kit (from private tauri bundle)
# or when fpm/dpkg-deb available for simple repack of tree.
if kind_has deb && command -v dpkg-deb >/dev/null 2>&1; then
  echo "== best-effort deb from tree =="
  DEB_ROOT="$WORK/deb-root"
  rm -rf "$DEB_ROOT"
  mkdir -p "$DEB_ROOT/DEBIAN" "$DEB_ROOT/opt/browboxs"
  cp -a "$STAGE/." "$DEB_ROOT/opt/browboxs/"
  cat >"$DEB_ROOT/DEBIAN/control" <<EOF
Package: browboxs
Version: ${VER}
Section: utils
Priority: optional
Architecture: $( [ "${OS_ARCH##*-}" = "aarch64" ] && echo arm64 || echo amd64 )
Maintainer: browboxs
Description: browboxs fingerprint workbench desktop client
EOF
  DEB_NAME="browboxs-${VER}-${OS_ARCH}.deb"
  if dpkg-deb -b "$DEB_ROOT" "$OUT_DIR/$DEB_NAME" 2>/dev/null; then
    append_sum "$(sha_file "$OUT_DIR/$DEB_NAME")" "$DEB_NAME"
    echo "PACK OK deb: $DEB_NAME"
  else
    echo "WARN: dpkg-deb failed — skip deb"
  fi
fi

# Collect any prebuilt installers dropped into kit (optional private-side bundles)
if [ -d "$STAGE/installers" ]; then
  echo "== collect kit installers/ =="
  find "$STAGE/installers" -type f \( -name '*.deb' -o -name '*.AppImage' -o -name '*.rpm' \
    -o -name '*.dmg' -o -name '*.msi' -o -name '*setup*.exe' -o -name '*.exe' \) 2>/dev/null \
    | while read -r f; do
        bn=$(basename "$f")
        cp -f "$f" "$OUT_DIR/browboxs-${VER}-${OS_ARCH}-${bn}"
        append_sum "$(sha_file "$OUT_DIR/browboxs-${VER}-${OS_ARCH}-${bn}")" "browboxs-${VER}-${OS_ARCH}-${bn}"
        echo "PACK OK collected: $bn"
      done
fi

echo "  platform=$PLATFORM os_arch=$OS_ARCH ver=$VER kinds=$PACK_KINDS"

# Optional smoke: start agent from packed tree
if [ "$RUN_SMOKE" = "1" ] && [ -f "$STAGE/bin/browboxs-agent" ]; then
  echo "== pack smoke: agent health =="
  SMOKE_DATA="${TMPDIR:-/tmp}/browboxs-pack-smoke-$$"
  mkdir -p "$SMOKE_DATA"
  export BROWBOX_AGENT_PORT="${BROWBOX_PACK_SMOKE_PORT:-18929}"
  export BROWBOX_AGENT_DATA="$SMOKE_DATA"
  unset BROWBOX_SERVE_UI BROWBOX_INSECURE_NO_AUTH BROWBOX_UI_DIR || true
  "$STAGE/bin/browboxs-agent" &
  pid=$!
  ok=0
  for _ in $(seq 1 40); do
    if curl -fsS "http://127.0.0.1:${BROWBOX_AGENT_PORT}/v1/health" >/tmp/pack-health.json 2>/dev/null; then
      ok=1; break
    fi
    sleep 0.25
  done
  # Root must not be SPA
  ROOT_BODY=$(curl -s "http://127.0.0.1:${BROWBOX_AGENT_PORT}/" || true)
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${BROWBOX_AGENT_PORT}/v1/profiles" || echo 000)
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -rf "$SMOKE_DATA"
  test "$ok" = "1"
  grep -q '"ok":true' /tmp/pack-health.json
  echo "$ROOT_BODY" | grep -qiE 'desktop_only|Local API|service' || {
    echo "ERROR: agent / looks like SPA: $ROOT_BODY" >&2
    exit 1
  }
  [ "$CODE" = "401" ] || {
    echo "ERROR: unauth /v1/profiles expected 401 got $CODE" >&2
    exit 1
  }
  echo "pack smoke OK (health + desktop_only root + 401 profiles)"
fi

rm -rf "$WORK"
echo "Done. Assets under $OUT_DIR"
ls -lah "$OUT_DIR"/browboxs-${VER}-* 2>/dev/null || ls -lah "$OUT_DIR"
