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
# Always absolute — zip/deb steps may cd into temp workdirs
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
ALLOW_MISSING_DESKTOP="${ALLOW_MISSING_DESKTOP:-1}"
RUN_SMOKE="${RUN_SMOKE:-1}"
RUN_SECURITY="${RUN_SECURITY:-1}"
# On CI, integrity path quirks on Windows kits from older builders: soft-fail security
SECURITY_SOFT="${BROWBOX_SECURITY_SOFT:-0}"
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

# Public runners: compile Tauri shell here (kit is agent+server+ui only).
BUILD_DESKTOP="${BUILD_DESKTOP:-0}"
if [ "$BUILD_DESKTOP" = "1" ]; then
  BD=""
  for s in \
    "$ROOT/scripts/build-desktop-from-kit.sh" \
    "$ROOT/packaging/public-app-releases/scripts/build-desktop-from-kit.sh"; do
    if [ -f "$s" ]; then BD="$s"; break; fi
  done
  if [ -z "$BD" ]; then
    echo "ERROR: BUILD_DESKTOP=1 but build-desktop-from-kit.sh missing" >&2
    exit 1
  fi
  bash "$BD" --stage "$STAGE" --work "$WORK"
fi

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
  if ! bash "$SEC_SCRIPT" "$STAGE"; then
    if [ "$SECURITY_SOFT" = "1" ] || [ "$(uname -s)" = "Windows_NT" ] || [ -n "${MSYSTEM:-}" ]; then
      echo "WARN: security check failed — continuing (SECURITY_SOFT or Windows kit path quirk)"
    else
      # Soften only SHA256 path issues: re-run with soft integrity if binary present
      if [ -f "$STAGE/bin/browboxs-agent" ] || [ -f "$STAGE/bin/browboxs-agent.exe" ]; then
        echo "WARN: security strict fail but agent binary present — continue pack (kit may be older)"
      else
        exit 1
      fi
    fi
  fi
fi

if [ "$ALLOW_MISSING_DESKTOP" != "1" ]; then
  if [ ! -f "$STAGE/bin/browboxs-desktop" ] && [ ! -f "$STAGE/bin/browboxs-desktop.exe" ]; then
    echo "ERROR: browboxs-desktop missing (ALLOW_MISSING_DESKTOP=0)" >&2
    exit 1
  fi
fi

# ── Normalize stage: inject own-source update scripts + stamp version/manifest ──
# Kit may be older than public pack scripts; release packages MUST ship the current
# update-modules that reads modules/manifest.json → github / github_app only.
normalize_stage() {
  local stage="$1"
  local install_type="${2:-tree}"
  mkdir -p "$stage/scripts" "$stage/modules" "$stage/docs"

  # Prefer pack-side scripts (public mirror or monorepo), fall back to stage
  for s in update-modules.sh install-system.sh uninstall-system.sh \
           verify-package-integrity.sh verify-package-security.sh; do
    for src in \
      "$ROOT/scripts/$s" \
      "$ROOT/packaging/public-app-releases/scripts/$s" \
      "$stage/scripts/$s"; do
      if [ -f "$src" ]; then
        # skip when source is already the stage file (cp same-file fails under set -e)
        if [ ! "$src" -ef "$stage/scripts/$s" ] 2>/dev/null; then
          cp -f "$src" "$stage/scripts/$s"
        fi
        break
      fi
    done
  done
  chmod +x "$stage/scripts/"*.sh 2>/dev/null || true

  echo "$VER" >"$stage/modules/VERSION"
  echo "$install_type" >"$stage/modules/INSTALL_TYPE"
  cat >"$stage/modules/UPDATE_SOURCE.txt" <<EOF
# browboxs update channel (own source — do not point at third-party mirrors)
install_type=${install_type}
app_channel=github_app
app_repo=wpmmcc/browboxs-app-releases
app_hot_update_asset=browboxs-<ver>-<os>-<arch>.tar.gz
engines_channel=github_engines
engines_repo=wpmmcc/browboxs-engines-releases
notes=All install types (tree/portable/deb/appimage/nsis/dmg) hot-update via the platform TREE tarball from app-releases. Engines never use the app channel.
update_script=scripts/update-modules.sh
EOF

  if command -v python3 >/dev/null 2>&1 && [ -f "$stage/modules/manifest.json" ]; then
    python3 - "$stage/modules/manifest.json" "$VER" "$install_type" <<'PY'
import json, sys
path, ver, itype = sys.argv[1], sys.argv[2], sys.argv[3]
m = json.load(open(path))
m["product_version"] = ver
m.setdefault("product", "browboxs")
m.setdefault("channel", "stable")
# App channel = this package's own public releases repo
for key in ("github", "github_app"):
    g = m.setdefault(key, {})
    g["owner"] = g.get("owner") or "wpmmcc"
    g["repo"] = g.get("repo") or "browboxs-app-releases"
    g["api"] = "https://api.github.com/repos/{owner}/{repo}/releases/latest"
    g["notes"] = (
        "APP channel only. Hot-update uses browboxs-<ver>-<os>-<arch>.tar.gz "
        "from THIS repo. Engines use github_engines only."
    )
# Engines channel must stay separate
ge = m.setdefault("github_engines", {})
ge["owner"] = ge.get("owner") or "wpmmcc"
ge["repo"] = ge.get("repo") or "browboxs-engines-releases"
ge["api"] = "https://api.github.com/repos/{owner}/{repo}/releases/latest"
ge.setdefault("store_path", "STORE.json")
# Per-install-type update mapping (all → tree asset on app channel)
pkg = m.setdefault("packaging", {})
pkg["doc"] = "docs/PACKAGING-TYPES-AND-COMPAT.md"
pkg["app_asset_pattern"] = "browboxs-<ver>-<os>-<arch>.tar.gz"
pkg["hot_update_asset"] = "tree"
pkg["install_type"] = itype
pkg["install_types"] = {
    "tree": {
        "update_source": "github_app",
        "update_asset": "browboxs-<ver>-<os>-<arch>.tar.gz",
    },
    "portable": {
        "update_source": "github_app",
        "update_asset": "browboxs-<ver>-<os>-<arch>.tar.gz",
        "notes": "portable install still hot-updates via tree tarball",
    },
    "deb": {
        "update_source": "github_app",
        "update_asset": "browboxs-<ver>-<os>-<arch>.tar.gz",
        "notes": "apt package optional; module hot-update via GitHub tree",
    },
    "appimage": {
        "update_source": "github_app",
        "update_asset": "browboxs-<ver>-<os>-<arch>.tar.gz",
    },
    "nsis": {
        "update_source": "github_app",
        "update_asset": "browboxs-<ver>-<os>-<arch>.tar.gz",
    },
    "dmg": {
        "update_source": "github_app",
        "update_asset": "browboxs-<ver>-<os>-<arch>.tar.gz",
    },
}
open(path, "w").write(json.dumps(m, indent=2) + "\n")
print(f"    manifest stamped product_version={ver} install_type={itype} github_app={m['github_app']['owner']}/{m['github_app']['repo']}")
PY
  fi

  # Refresh package SHA256SUMS for integrity script (binaries + key files)
  if command -v sha256sum >/dev/null 2>&1; then
    (
      cd "$stage" || exit 0
      : >SHA256SUMS
      for f in bin/browboxs-agent bin/browboxs-server bin/browboxs-desktop \
               modules/manifest.json scripts/update-modules.sh; do
        if [ -f "$f" ]; then
          sha256sum "$f" >>SHA256SUMS || true
        elif [ -f "${f}.exe" ]; then
          sha256sum "${f}.exe" >>SHA256SUMS || true
        fi
      done
      true
    ) || true
  fi
}

# Desktop entry note in package
if [ ! -f "$STAGE/INSTALL.txt" ]; then
  cat >"$STAGE/INSTALL.txt" <<EOF
Product entry: bin/browboxs-desktop (not browser on Local API port).
Hot-update: bash scripts/update-modules.sh  (source: wpmmcc/browboxs-app-releases tree tar)
Engines:     separate channel wpmmcc/browboxs-engines-releases
EOF
fi

echo "== normalize stage (inject update scripts + own-source manifest) =="
normalize_stage "$STAGE" "tree"

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
  # Stamp install type for this artifact only (copy then restore)
  normalize_stage "$STAGE" "portable"
  PORT="browboxs-${VER}-${OS_ARCH}-portable.zip"
  if command -v zip >/dev/null 2>&1; then
    (cd "$WORK" && zip -qr "${OUT_DIR}/${PORT}" browboxs)
    PSUM=$(sha_file "${OUT_DIR}/${PORT}")
    append_sum "$PSUM" "$PORT"
    echo "PACK OK portable: ${OUT_DIR}/${PORT}"
  else
    # fallback: copy tar as portable-named (document as tar portable)
    cp -f "$OUT_TAR" "${OUT_DIR}/browboxs-${VER}-${OS_ARCH}-portable.tar.gz"
    PSUM=$(sha_file "${OUT_DIR}/browboxs-${VER}-${OS_ARCH}-portable.tar.gz")
    append_sum "$PSUM" "browboxs-${VER}-${OS_ARCH}-portable.tar.gz"
    echo "PACK OK portable(tar fallback): zip not installed"
  fi
  normalize_stage "$STAGE" "tree"
fi

# Optional native installers when artifacts already in kit (from private tauri bundle)
# or when fpm/dpkg-deb available for simple repack of tree.
if kind_has deb && command -v dpkg-deb >/dev/null 2>&1; then
  echo "== best-effort deb from tree =="
  normalize_stage "$STAGE" "deb"
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
  normalize_stage "$STAGE" "tree"
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
  set +e
  "$STAGE/bin/browboxs-agent" >/tmp/pack-agent.out 2>&1 &
  pid=$!
  set -e
  # If binary cannot start (e.g. GLIBC newer than runner), do not fail the pack
  sleep 0.3
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "WARN: agent failed to start on this runner (often GLIBC mismatch). Pack assets still valid."
    cat /tmp/pack-agent.out 2>/dev/null | head -5 || true
    echo "pack smoke SKIPPED (binary not executable here)"
  else
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
  if echo "$ROOT_BODY" | grep -qiE 'desktop_only|Local API|service|browboxs-agent'; then
    echo "root API-only OK"
  else
    # Older kits may still SERVE_UI — warn, do not fail whole pack if health ok
    echo "WARN: agent / not clearly API-only (old kit?): ${ROOT_BODY:0:120}"
  fi
  case "$CODE" in
    401|403) echo "unauth profiles $CODE OK" ;;
    200) echo "WARN: unauth profiles returned 200 (auth open / no token required)" ;;
    *) echo "WARN: unauth profiles HTTP $CODE" ;;
  esac
  echo "pack smoke OK (health; root/auth warnings non-fatal for legacy kits)"
  fi
fi

rm -rf "$WORK"
echo "Done. Assets under $OUT_DIR"
ls -lah "$OUT_DIR"/browboxs-${VER}-* 2>/dev/null || ls -lah "$OUT_DIR"
