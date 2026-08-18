# desktop-shell (public pack)

Thin **Tauri window** compiled on GitHub hosted runners (one cell per OS/arch).

Does **not** contain agent/server source. Pack job:

1. Downloads `kit-<os>-<arch>.tar.gz` (agent + server + `ui/desktop`)
2. Copies UI → `dist/`, binaries → `src-tauri/binaries/`
3. `npx tauri build --no-bundle`
4. Injects `browboxs-desktop` into the user install tree

Local monorepo still owns `apps/desktop` for development. This tree is the public compile surface only.
