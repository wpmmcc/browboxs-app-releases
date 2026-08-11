# 打包类型规范 · 安装兼容矩阵 · Runner 绑定

> **状态**：产品打包合同（2026-08-11）  
> **对标**：Clash Verge Rev 安装页（Win/Linux/mac 多格式 + 系统要求 + 源码编译）· Donut/Shard Tauri 矩阵 · 本仓 hybrid 私有 kit → 公开 free-runner  
> **SoT 姐妹**：[`REPO-AND-BINARY-ARCHITECTURE.md`](./REPO-AND-BINARY-ARCHITECTURE.md) · [`PACKAGING-HYBRID-PRIVATE-PUBLIC.md`](./PACKAGING-HYBRID-PRIVATE-PUBLIC.md) · [`FRONTEND-ARCHITECTURE.md`](./FRONTEND-ARCHITECTURE.md) · [`INSTALLERS-AND-UPDATES.md`](./INSTALLERS-AND-UPDATES.md)

---

## 0. 原则

1. **三大平台**：Windows · Linux · macOS；每平台再拆 **架构 × 安装形态**。  
2. **一 cell 一 runner**：每个「平台 + 架构 + 主安装形态组」在 **原生 OS runner** 上打包/封装（禁止指望单机交叉出全部系统安装器）。  
3. **公开仓双路径**：  
   - **A. 安装文件**：GitHub Release 多格式安装包（本文主表）  
   - **B. 源码编译**：公开 pack 仓可含 **仅 pack 脚本 + 从 kit 组装**；**完整业务源码不在公开仓**。用户若要「从源码编译」，走 **文档化的 core 私有协作 / 未来开源源码仓**；公开仓 README 明确：默认交付是 **二进制安装包**，源码路径见 CONTRIBUTING 式指南（可选公开 `build-from-kit` 说明）。  
4. **私有侧先安全打包**：core 私有仓 `make-kit` → strip / harden / 混淆钩子 → kit → `sync-to-public-releases` → 公开 `pack-and-test`。  
5. **产品入口**：所有安装形态最终启动 **`browboxs-desktop`**（非浏览器控制台）。

---

## 1. 安装包内核心内容（所有类型共通）

无论 deb / nsis / dmg / portable，**运行时树**一致：

```text
browboxs/
  bin/browboxs-desktop     # 入口
  bin/browboxs-agent       # 本机执行 · RPA · 开核
  bin/browboxs-server      # 可选主机 · 节点 · RBAC
  ui/desktop/              # 前端静态（Tauri frontendDist）
  modules/manifest.json
  engines/                 # Slim 或首启商店
  scripts/install-system.sh …
  HARDENING.txt · SHA256SUMS · INSTALL.txt
```

| 层 | 在哪构建 | 说明 |
|----|----------|------|
| 前端 UI | 私有 core `apps/desktop` Vite | 仅静态资源进 kit |
| 壳 desktop | 私有 Tauri build | 进 kit |
| agent/server | 私有 cargo release + harden | 进 kit |
| 系统安装器外壳 | **公开 runner** 或私有应急 | 把 kit 树打成 deb/nsis/dmg… |

---

## 2. 打包类型总表（Clash Verge 风格）

### 2.1 Windows

| ID | 架构 | 形态 | 文件名约定 | 优先级 | Runner | 系统要求 |
|----|------|------|------------|--------|--------|----------|
| `win-x64-nsis` | x86_64 | NSIS 安装包 | `browboxs-<ver>-windows-x86_64-setup.exe` | **P0** | `windows-latest` | **Windows 10 1809+ / 11**；x64 |
| `win-x64-msi` | x86_64 | MSI | `browboxs-<ver>-windows-x86_64.msi` | P1 | 同上 cell | 同上；企业静默装 |
| `win-x64-portable` | x86_64 | 便携 ZIP | `browboxs-<ver>-windows-x86_64-portable.zip` | **P0** | 同上 cell | 解压即用；数据目录旁路或 `%APPDATA%` |
| `win-x64-tree` | x86_64 | 安装树 tar/zip | `browboxs-<ver>-windows-x86_64.tar.gz` | **P0** | 同上 | 热更新主资产 |
| `win-arm64-nsis` | aarch64 | NSIS | `browboxs-<ver>-windows-aarch64-setup.exe` | P2 | `windows-11-arm` 若可用 | Win11 ARM |
| `win-x64-webview2-fixed` | x86_64 | 内置 WebView2 的安装包 | `…-setup-webview2.exe` | P2 | windows-latest | 系统无法装 WebView2 时（对标 Clash `fixed_webview2`） |

**Windows 兼容说明（必须写进公开 INSTALL）：**

- **不支持 Windows 7/8**（对标 Clash Verge：请升级 Win10/11）。  
- 默认依赖 **Evergreen WebView2**（Win10/11 通常已装）；缺失时引导下载或使用 `webview2-fixed` 包。  
- 未签名时 SmartScreen：**更多信息 → 仍要运行**（文档写明）。  
- 便携版：不写系统卸载项；**热更新可支持 tar 通道**，便携 zip 可要求手动覆盖（与 Clash portable 类似）。

### 2.2 Linux

| ID | 架构 | 形态 | 文件名约定 | 优先级 | Runner | 发行版/要求 |
|----|------|------|------------|--------|--------|-------------|
| `linux-x64-deb` | x86_64 | Debian 包 | `browboxs_<ver>_amd64.deb` 或 `browboxs-<ver>-linux-x86_64.deb` | **P0** | `ubuntu-22.04` | Ubuntu/Debian/Deepin 等；`sudo apt install -y ./…deb` |
| `linux-arm64-deb` | aarch64 | deb | `…_arm64.deb` | **P0** | `ubuntu-24.04-arm` | ARM 服务器/桌面 |
| `linux-x64-appimage` | x86_64 | AppImage | `browboxs-<ver>-linux-x86_64.AppImage` | **P0** | `ubuntu-22.04` | 任意 glibc 发行版；`chmod +x` 后运行 |
| `linux-arm64-appimage` | aarch64 | AppImage | `…-linux-aarch64.AppImage` | **P0** | `ubuntu-24.04-arm` | 原生 ARM runner（**不可靠交叉**） |
| `linux-x64-rpm` | x86_64 | RPM | `browboxs-<ver>-1.x86_64.rpm` | P1 | `ubuntu-22.04` + rpm 工具 或 fedora runner | Fedora/RHEL/openSUSE：`dnf install ./…rpm` |
| `linux-arm64-rpm` | aarch64 | RPM | `…aarch64.rpm` | P2 | arm runner | 同上 |
| `linux-x64-tree` | x86_64 | 安装树 tar.gz | `browboxs-<ver>-linux-x86_64.tar.gz` | **P0** | 同 x64 cell | 通用；`install-system.sh` |
| `linux-arm64-tree` | aarch64 | tar.gz | `…-linux-aarch64.tar.gz` | **P0** | arm cell | 同上 |
| `linux-aur` | — | AUR 说明 | 文档 + PKGBUILD 可选 | P2 | 社区 | Arch/Manjaro（文档指引，非必须官方构建） |

**Linux 兼容说明：**

- **glibc** 基线：以 **Ubuntu 22.04** 构建的 deb/AppImage 为准（约 glibc 2.35+）；更老发行版用 AppImage 或自编译。  
- 桌面依赖：WebKitGTK / libgtk（Tauri）；无头服务器仅 agent CLI 场景另文说明。  
- AppImage：FUSE 3；失败时 `./xxx.AppImage --appimage-extract-and-run`。  
- 不提供 armv7（对标我们产品矩阵；Clash 有 armhf 我们 **P3 不做**）。

### 2.3 macOS

| ID | 架构 | 形态 | 文件名约定 | 优先级 | Runner | 系统要求 |
|----|------|------|------------|--------|--------|----------|
| `mac-arm64-dmg` | aarch64 | DMG | `browboxs-<ver>-macos-aarch64.dmg` | **P0** | `macos-latest` | **macOS 12+**（对标 Clash 12+；11 不保证） |
| `mac-x64-dmg` | x86_64 | DMG | `browboxs-<ver>-macos-x86_64.dmg` | **P1** | `macos-latest` + target | Intel Mac |
| `mac-arm64-app` | aarch64 | .app 树 / tar | `browboxs-<ver>-macos-aarch64.app.tar.gz` | P1 | 同上 | 便携/脚本装 |
| `mac-x64-app` | x86_64 | .app tar | `…-macos-x86_64.app.tar.gz` | P2 | 同上 | Intel |
| `mac-arm64-tree` | aarch64 | 通用 tar 安装树 | `browboxs-<ver>-darwin-aarch64.tar.gz` | **P0** | 同上 | 热更新资产（os 名 darwin/macos 别名） |

**macOS 兼容说明：**

- 未公证时：系统拦启动 → **隐私与安全性 → 仍要打开**，或 `xattr -dr com.apple.quarantine "…/browboxs.app"`（对标 Shard/Clash 文档）。  
- Apple Silicon 默认下载 aarch64；Intel 下载 x64（勿混用）。  
- 最低版本冻结：**macOS 12**。

### 2.4 源码 / 开发者路径（公开仓必须写清）

| 路径 | 内容 | 说明 |
|------|------|------|
| **推荐用户** | 上表安装文件 | 安全加固后的二进制 |
| **从 kit 复现** | 公开仓 `scripts/pack-kit-to-release.sh` + Release 中的 kit 中转 | 无完整业务源码 |
| **完整源码编译** | 私有 core 仓（或未来开源源码仓） | `cargo build` + `npm run tauri build`；见 `docs/BUILD-FROM-SOURCE.md` |
| **包管理器** | winget / brew / AUR | P2 社区渠道；官方首发以 GitHub Release 为准 |

---

## 3. Runner 矩阵（一 cell 一 runner）

> 公开 `pack-and-test` 与私有 `prepare-kits` **平台 key 对齐**。  
> 私有 kit 按 **os+arch** 出一份；公开在同一 runner 上把 kit 扩成该平台 **多种形态**（deb+AppImage+tree 可同 job）。

| matrix cell ID | runs-on | kit 名 | 本 cell 产出的打包类型 ID |
|----------------|---------|--------|---------------------------|
| `linux-x86_64` | `ubuntu-22.04` | `kit-linux-x86_64.tar.gz` | tree + deb + AppImage（+ rpm P1） |
| `linux-aarch64` | `ubuntu-24.04-arm` | `kit-linux-aarch64.tar.gz` | tree + deb + AppImage |
| `windows-x86_64` | `windows-latest` | `kit-windows-x86_64.tar.gz` | tree + nsis + portable zip（+ msi P1） |
| `darwin-aarch64` | `macos-latest` | `kit-darwin-aarch64.tar.gz` | tree + dmg（+ app.tar P1） |
| `darwin-x86_64` | `macos-latest` + target | `kit-darwin-x86_64.tar.gz` | tree + dmg |

**禁止**：在 `ubuntu-22.04` 上产出 Windows nsis 或 macOS dmg 作为正式用户包。

私有 `prepare-kits` 与上表 **同一 5 cell**（仅编译+harden kit，不打 deb/nsis）。

---

## 4. 端到端流水线（安全 → 同步 → Runner）

```text
① 私有 core
   cargo + npm + tauri (按平台)
   secure-harden-release · obfuscate hook · verify-package-security
   make-kit → dist/kits/kit-<os>-<arch>.tar.gz + HARDENING.txt
        │
        ▼
② scripts/sync-to-public-releases.sh
   · rsync packaging/public-app-releases → 公开仓 git（脚本/workflow）
   · gh release upload kits-v<ver>  (prerelease 中转)
   · gh workflow run pack-and-test / repository_dispatch
        │
        ▼
③ 公开 app-releases free runners（上表每 cell 一 runner）
   download kit → verify sha → pack-kit-to-release
   → 命名规范化 → verify-package-security → smoke
   → 聚合 Release v<ver> + RELEASE-SHA256SUMS + INSTALL 说明
```

---

## 5. 资产命名冻结

```text
# 安装树（热更新首选）
browboxs-<ver>-linux-x86_64.tar.gz
browboxs-<ver>-linux-aarch64.tar.gz
browboxs-<ver>-windows-x86_64.tar.gz
browboxs-<ver>-windows-x86_64-portable.zip
browboxs-<ver>-darwin-aarch64.tar.gz    # 与 macos 别名并存于 updater

# 系统安装器
browboxs-<ver>-linux-x86_64.deb | .AppImage | .rpm
browboxs-<ver>-windows-x86_64-setup.exe | .msi
browboxs-<ver>-macos-aarch64.dmg | .app.tar.gz

# 汇总
RELEASE-SHA256SUMS.txt
```

`<ver>` 与 tag `v0.1.0` 对齐（无 `v` 前缀进文件名）。

---

## 6. 前端架构 ↔ 安装包

| 前端规范 | 安装包落实 |
|----------|------------|
| 唯一入口桌面壳 | 所有类型快捷方式/`.desktop`/`Exec=` → `browboxs-desktop` |
| UI 在 frontendDist | kit 必含 `ui/desktop/`；Agent 默认不 SERVE_UI |
| 组件标准 / token | 私有仓构建时完成；包内仅为 dist |
| IPC Bearer | desktop spawn 清 SERVE_UI；打包脚本禁止写 `SERVE_UI=1` |

详见 [`FRONTEND-ARCHITECTURE.md`](./FRONTEND-ARCHITECTURE.md) §0 · [`DESKTOP-CLIENT-ARCHITECTURE.md`](./DESKTOP-CLIENT-ARCHITECTURE.md)。

---

## 7. 验收清单

- [ ] 每 P0 类型在对应 runner 产出且 sha256 入 RELEASE-SHA256SUMS  
- [ ] 公开 INSTALL 写明：Win10+、macOS12+、Linux glibc 基线、WebView2、未签名提示  
- [ ] 解压 tree 后存在三二进制 + ui/desktop  
- [ ] `verify-package-security` PASS  
- [ ] 浏览器打开 Agent 根路径不是工作台  
- [ ] 同步脚本可从私有 monorepo 一键 push 脚本 + 上传 kit + dispatch  

---

## 8. 参考

| 来源 | 借鉴 |
|------|------|
| Clash Verge Rev install | 三大平台 × 多格式；Win7 砍掉；fixed WebView2；deb/rpm/AUR；mac 12+；源码编译入口 |
| Donut release | deb/rpm/AppImage/dmg/nsis + portable zip；矩阵 runner |
| Shard release | dmg/msi/AppImage/deb + portable；安装说明含 quarantine/SmartScreen |
| 本仓 Opensource | fury shell/core 分轨；simprint packager ZIP+SHA256 |

---

*变更本文件 = 变更对外安装合同。实现以 `packaging/public-app-releases` workflow 与 `scripts/sync-to-public-releases.sh` 为准。*
