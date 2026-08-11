# browboxs-app-releases

**Public installers only** — no full product source tree.

| Channel | Content |
|---------|---------|
| Release `v*` | End-user portable packages: `browboxs-<ver>-<os>-<arch>.tar.gz` |
| Prerelease `kits-v*` | Internal transfer kits from private monorepo (binaries + UI assets) |

## Hybrid pipeline (private minutes → public packaging)

1. **Private** [`browboxs-v2-private`](https://github.com/wpmmcc/browboxs-v2-private) runs `prepare-kits`  
   → compiles agent/server (+ UI) per platform → uploads `kit-*.tar.gz` here as prerelease  
   → `repository_dispatch` `kits-ready`
2. **This public repo** runs `pack-and-test` (uses **public** Actions minutes)  
   → renames kits to user assets  
   → **install smoke** (extract / install-system / agent `/v1/health`)  
   → publishes `v*` Release

See monorepo doc: `docs/PACKAGING-HYBRID-PRIVATE-PUBLIC.md`.

## Manual re-pack

```bash
gh workflow run pack-and-test.yml -R wpmmcc/browboxs-app-releases \
  -f version=0.1.0 -f kit_tag=kits-v0.1.0
```

## Engines

Fingerprint engines: [browboxs-engines-releases](https://github.com/wpmmcc/browboxs-engines-releases) (separate channel).
