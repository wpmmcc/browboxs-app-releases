# Full matrix cross + pack test 0.2.4

| Platform | Binary source | Host Linux cross? | Pack runner | Install test |
|----------|---------------|-------------------|-------------|--------------|
| linux-x86_64 | Docker Ubuntu 22.04 | N/A (native in container) | ubuntu-22.04 | live expected OK (glibc≤2.34) |
| linux-aarch64 | Host cross + aarch64-linux-gnu-gcc | YES | ubuntu-24.04-arm | live OK |
| windows-x86_64 | Host cross + mingw | YES | windows-latest | live OK |
| windows-aarch64 | Host Linux | NO (no toolchain/SDK) | windows-11-arm | needs ARM Windows runner |
| darwin-aarch64 | Host Linux | NO (no Apple SDK) | macos-latest | needs mac prepare-kits |
| darwin-x86_64 | Host Linux | NO | macos-latest | needs mac prepare-kits |
