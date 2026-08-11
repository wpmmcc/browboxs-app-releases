# Cross-compile pack experiment (no Rust source)

This branch tests:

1. Pure-Rust **agent/server** built via host cross-compile (linux-x86_64 / linux-aarch64 / windows-x86_64-gnu).
2. Kits uploaded as binary-only `kits-v0.2.3-cross` (no `crates/`, no monorepo source).
3. Public GitHub Actions `pack-and-test` on native runners → user install packages.
4. Product smoke on packages (structure / update source / optional live API).

## Architecture (aligned)

- Server node: one data directory per instance; default local node.
- Server + agent: pure Rust binaries (cross-compiled offline).
- Public repo: pack scripts + UI assets in kits + prebuilt binaries only.

## Trigger

```bash
gh workflow run pack-and-test.yml --ref test/cross-pack-0.2.3 \
  -f version=0.2.3 \
  -f kit_tag=kits-v0.2.3-cross \
  -f publish=true \
  -f allow_partial=true \
  -f require_desktop=false
```

Desktop is intentionally absent (Tauri not pure-Rust cross).
