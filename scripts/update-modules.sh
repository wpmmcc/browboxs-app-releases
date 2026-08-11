#!/usr/bin/env bash
# Hot-update installed browboxs tree from the package's own app-releases source.
# Reads modules/manifest.json → github.owner/repo (default wpmmcc/browboxs-app-releases).
# Selects platform tree asset: browboxs-*-<os>-<arch>.tar.gz (not portable/deb/dmg).
#
# Usage:
#   BROWBOX_INSTALL_ROOT=$HOME/.local/opt/browboxs bash scripts/update-modules.sh --check
#   BROWBOX_INSTALL_ROOT=... bash scripts/update-modules.sh
#   BROWBOX_APP_RELEASES_REPO=owner/repo bash scripts/update-modules.sh
#   BROWBOX_UPDATE_TAG=v0.1.0  # pin tag instead of latest
set -euo pipefail

ROOT="${BROWBOX_INSTALL_ROOT:-${BROWBOX_PREFIX:-$HOME/.local/opt/browboxs}}"
MANIFEST="${BROWBOX_MODULES_MANIFEST:-$ROOT/modules/manifest.json}"
CHECK_ONLY=0
APPLY=1
[ "${1:-}" = "--check" ] && { CHECK_ONLY=1; APPLY=0; }
[ "${1:-}" = "--dry-run" ] && { CHECK_ONLY=1; APPLY=0; }

if [ ! -d "$ROOT/bin" ]; then
  echo "ERROR: not an install root: $ROOT (missing bin/)" >&2
  exit 1
fi

# Resolve app releases repo from manifest (own source) then env override
APP_REPO="${BROWBOX_APP_RELEASES_REPO:-}"
if [ -z "$APP_REPO" ] && [ -f "$MANIFEST" ]; then
  APP_REPO=$(python3 - "$MANIFEST" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
g=m.get("github") or m.get("github_app") or {}
owner=g.get("owner") or "wpmmcc"
repo=g.get("repo") or "browboxs-app-releases"
print(f"{owner}/{repo}")
PY
)
fi
APP_REPO="${APP_REPO:-wpmmcc/browboxs-app-releases}"

ENGINES_REPO="${BROWBOX_ENGINES_RELEASES_REPO:-}"
if [ -z "$ENGINES_REPO" ] && [ -f "$MANIFEST" ]; then
  ENGINES_REPO=$(python3 - "$MANIFEST" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
g=m.get("github_engines") or {}
if not g:
  print("")
else:
  print(f"{g.get('owner','wpmmcc')}/{g.get('repo','browboxs-engines-releases')}")
PY
)
fi

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in x86_64|amd64) ARCH=x86_64 ;; aarch64|arm64) ARCH=aarch64 ;; esac
case "$OS" in msys*|mingw*|cygwin*) OS=windows ;; darwin) OS=darwin ;; linux) OS=linux ;; esac

echo "==> install root: $ROOT"
echo "    manifest:     $MANIFEST"
echo "    app source:   $APP_REPO  (app channel — this install type updates from here)"
echo "    engines src:  ${ENGINES_REPO:-n/a}"
echo "    platform:     ${OS}-${ARCH}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Prefer pinned tag; else GitHub latest
if [ -n "${BROWBOX_UPDATE_TAG:-}" ]; then
  API="https://api.github.com/repos/${APP_REPO}/releases/tags/${BROWBOX_UPDATE_TAG}"
  echo "    release tag:  $BROWBOX_UPDATE_TAG (pinned)"
else
  API="https://api.github.com/repos/${APP_REPO}/releases/latest"
  echo "    release:      latest"
fi

HDR=(-H "Accept: application/vnd.github+json")
if [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
  HDR+=(-H "Authorization: Bearer ${GH_TOKEN:-$GITHUB_TOKEN}")
fi

if ! curl -fsSL "${HDR[@]}" "$API" -o "$TMP/release.json"; then
  echo "ERROR: cannot fetch $API" >&2
  exit 1
fi

TAG=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tag_name",""))' "$TMP/release.json")
echo "    resolved tag: $TAG"

# Select platform product tree asset (not portable/deb/setup)
python3 - "$TMP/release.json" "$OS" "$ARCH" "$TMP" <<'PY'
import json,sys,re,urllib.request,hashlib,os
rel=json.load(open(sys.argv[1]))
osname, arch, outdir = sys.argv[2], sys.argv[3], sys.argv[4]
assets=rel.get("assets") or []
names=[a.get("name") or "" for a in assets]
print("    assets on release:")
for n in sorted(names):
    print(f"      - {n}")

def match(name: str) -> bool:
    low=name.lower()
    if not low.startswith("browboxs-"):
        return False
    if "component-" in low or "kit-" in low:
        return False
    # portable / installers are alternate install types — hot-update uses tree
    if "portable" in low or low.endswith(".deb") or low.endswith(".rpm"):
        return False
    if low.endswith(".appimage") or low.endswith(".msi") or low.endswith(".dmg"):
        return False
    if "setup" in low or low.endswith("-setup.exe"):
        return False
    # os
    os_ok = False
    if osname == "linux" and "linux" in low:
        os_ok = True
    if osname == "windows" and "windows" in low:
        os_ok = True
    if osname == "darwin" and ("darwin" in low or "macos" in low or "osx" in low):
        os_ok = True
    if not os_ok:
        return False
    # arch
    if arch == "x86_64" and not any(x in low for x in ("x86_64","amd64","x64")):
        return False
    if arch == "aarch64" and not any(x in low for x in ("aarch64","arm64")):
        return False
    return low.endswith(".tar.gz") or low.endswith(".tgz")

cands=[n for n in names if match(n)]
# Prefer exact tree browboxs-<ver>-<os>-<arch>.tar.gz without extra suffixes
cands.sort(key=lambda n: (n.count("-"), len(n)))
if not cands:
    print("ERROR: no platform tree tarball for", osname, arch, file=sys.stderr)
    print("HINT: release must publish browboxs-<ver>-%s-%s.tar.gz" % (
        "linux" if osname=="linux" else ("windows" if osname=="windows" else "darwin|macos"), arch), file=sys.stderr)
    sys.exit(2)
chosen=cands[0]
print(f"    selected:     {chosen}")
open(os.path.join(outdir,"SELECTED_ASSET"),"w").write(chosen)
# map name->asset
amap={a["name"]:a for a in assets if a.get("name")}
url=amap[chosen]["browser_download_url"]
open(os.path.join(outdir,"SELECTED_URL"),"w").write(url)
# sidecar
side=amap.get(chosen+".sha256")
if side:
    open(os.path.join(outdir,"SELECTED_SHA_URL"),"w").write(side["browser_download_url"])
PY

ASSET=$(cat "$TMP/SELECTED_ASSET")
URL=$(cat "$TMP/SELECTED_URL")
echo "    download:     $ASSET"

if [ "$CHECK_ONLY" = "1" ]; then
  echo "==> check only — update source OK, asset selected"
  LOCAL_VER="unknown"
  [ -f "$ROOT/modules/VERSION" ] && LOCAL_VER=$(tr -d '\n' <"$ROOT/modules/VERSION")
  [ -f "$MANIFEST" ] && LOCAL_VER=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("product_version","?"))' "$MANIFEST" 2>/dev/null || echo "$LOCAL_VER")
  echo "    local version:  $LOCAL_VER"
  echo "    remote tag:     $TAG"
  echo "    remote asset:   $ASSET"
  echo "    update source:  https://github.com/${APP_REPO}/releases"
  exit 0
fi

echo "    fetching…"
curl -fsSL "$URL" -o "$TMP/$ASSET"
if [ -f "$TMP/SELECTED_SHA_URL" ]; then
  curl -fsSL "$(cat "$TMP/SELECTED_SHA_URL")" -o "$TMP/${ASSET}.sha256"
  EXP=$(awk '{print $1}' "$TMP/${ASSET}.sha256" | tr 'A-F' 'a-f')
  GOT=$(sha256sum "$TMP/$ASSET" | awk '{print $1}')
  if [ "$EXP" != "$GOT" ]; then
    echo "ERROR: sha256 mismatch for $ASSET" >&2
    echo "  expected $EXP" >&2
    echo "  got      $GOT" >&2
    exit 1
  fi
  echo "    sha256 OK"
fi

# Snapshot before apply
SNAP="$ROOT/updates"
mkdir -p "$SNAP"
if [ -x "$ROOT/bin/browboxs-agent" ] || [ -f "$ROOT/bin/browboxs-agent" ]; then
  tar -C "$ROOT" -czf "$SNAP/previous-snapshot-modules.tar.gz" \
    bin modules ui scripts 2>/dev/null || true
fi

echo "    extract → $ROOT"
# Package layout: top-level browboxs/  (avoid tar|head SIGPIPE under pipefail)
FIRST_ENTRY=$(tar tzf "$TMP/$ASSET" 2>/dev/null | head -1 || true)
if [[ "$FIRST_ENTRY" == browboxs/ ]] || [[ "$FIRST_ENTRY" == browboxs/* ]]; then
  tar -xzf "$TMP/$ASSET" -C "$ROOT" --strip-components=1
else
  tar -xzf "$TMP/$ASSET" -C "$ROOT"
fi
# If a previous broken apply left a nested browboxs/, promote it once
if [ ! -x "$ROOT/bin/browboxs-agent" ] && [ -x "$ROOT/browboxs/bin/browboxs-agent" ]; then
  echo "    promote nested browboxs/ → install root"
  tar -C "$ROOT/browboxs" -cf - . | tar -C "$ROOT" -xf -
  rm -rf "$ROOT/browboxs"
fi

# Ensure update script self-source remains this repo; stamp product_version from modules/VERSION
if [ -f "$ROOT/modules/manifest.json" ]; then
  python3 - "$ROOT/modules/manifest.json" "$APP_REPO" "${ROOT}/modules/VERSION" <<'PY'
import json,sys,os
path, repo, ver_file = sys.argv[1], sys.argv[2], sys.argv[3]
owner, name = repo.split("/",1)
m=json.load(open(path))
m.setdefault("github",{})
m["github"]["owner"]=owner
m["github"]["repo"]=name
m["github"]["api"]="https://api.github.com/repos/{owner}/{repo}/releases/latest"
m.setdefault("github_app",{})
m["github_app"]["owner"]=owner
m["github_app"]["repo"]=name
m["github_app"]["api"]=m["github"]["api"]
if os.path.isfile(ver_file):
    ver=open(ver_file).read().strip()
    if ver:
        m["product_version"]=ver
open(path,"w").write(json.dumps(m,indent=2)+"\n")
print("    pinned manifest github →", repo, "product_version=", m.get("product_version"))
PY
fi

if [ -f "$ROOT/SHA256SUMS" ] && [ -x "$ROOT/scripts/verify-package-integrity.sh" ]; then
  echo "==> post-update integrity"
  bash "$ROOT/scripts/verify-package-integrity.sh" "$ROOT" || {
    echo "WARN: integrity soft-fail after extract (paths may differ)"
  }
fi

echo "==> update applied under $ROOT"
echo "    restart: $ROOT/bin/browboxs-desktop  or  $ROOT/bin/browboxs-start-agent"
echo "    source:  https://github.com/${APP_REPO}/releases/tag/${TAG}"
