# browboxs 安装指南（公开安装包仓）

> 对标 Clash Verge Rev 式「按操作系统拆分多种安装包 + 系统要求」。  
> 完整类型表：上游 monorepo `docs/PACKAGING-TYPES-AND-COMPAT.md`。  
> **产品入口始终是桌面客户端 `browboxs-desktop`**，不要用浏览器打开 Local API 端口当工作台。

本仓库 **只发布编译后的安装包与 pack 脚本**，不包含完整业务源码。源码编译见 monorepo `docs/BUILD-FROM-SOURCE.md`。

---

## 操作系统

### Windows

| 架构 | 推荐包 | 说明 |
|------|--------|------|
| **x64**（多数 PC） | `browboxs-*-windows-x86_64-setup.exe`（NSIS） | 安装向导 |
| x64 便携 | `browboxs-*-windows-x86_64-portable.zip` | 解压即用 |
| x64 热更新树 | `browboxs-*-windows-x86_64.tar.gz` | 与安装根同构 |
| arm64 | `…-windows-aarch64-setup.exe`（若发布） | Windows 11 ARM |

**系统要求**

- **Windows 10（1809+）或 Windows 11**。不支持 Windows 7/8。  
- 需要 **WebView2 Runtime**（Win10/11 通常已预装）。若无法打开窗口，安装 [Evergreen WebView2](https://developer.microsoft.com/microsoft-edge/webview2/) 或使用带 `webview2` 内置标记的安装包（若提供）。  
- 未代码签名时 SmartScreen 可能拦截：选择 **更多信息 → 仍要运行**。

**安装后**

- 开始菜单 / 桌面快捷方式启动 **browboxs**（`browboxs-desktop`）。  
- 不要收藏 `http://127.0.0.1:18910` 当控制台。

---

### Linux

| 发行版族 | 架构 | 推荐包 | 安装命令示例 |
|----------|------|--------|--------------|
| Debian / Ubuntu / Deepin | x64 | `*.deb` | `sudo apt install -y ./browboxs-…-amd64.deb` |
| Debian / Ubuntu | arm64 | `*.deb` | 同上 |
| 通用 | x64 / arm64 | `*.AppImage` | `chmod +x browboxs-…AppImage && ./browboxs-…AppImage` |
| Fedora / RHEL / openSUSE | x64 | `*.rpm`（若发布） | `sudo dnf install ./browboxs-….rpm` |
| 任意 | x64 / arm64 | `browboxs-…-linux-….tar.gz` | 解压后 `bash scripts/install-system.sh` |
| Arch / Manjaro | — | 可选 AUR（社区） | 见文档；官方以 GitHub Release 为准 |

**系统要求**

- 推荐 **glibc ≥ 2.35** 量级（以 Ubuntu 22.04 构建为基线）。  
- 桌面版需要 **WebKitGTK / GTK** 相关库（Tauri）。  
- AppImage 需要可执行权限；FUSE 异常时可用 `--appimage-extract-and-run`。

---

### macOS

| 芯片 | 推荐包 |
|------|--------|
| Apple Silicon (M 系列) | `browboxs-*-macos-aarch64.dmg` |
| Intel | `browboxs-*-macos-x86_64.dmg` |

**系统要求**

- **macOS 12 及以上**。  
- 未公证时：系统可能提示已损坏/无法打开 → **系统设置 → 隐私与安全性 → 仍要打开**，或：  
  `xattr -dr com.apple.quarantine "/Applications/browboxs.app"`  
- 将 App 拖入「应用程序」后从启动台打开。

---

## 校验完整性

```bash
# 示例
sha256sum -c browboxs-0.1.0-linux-x86_64.tar.gz.sha256
# 或对照 Release 中的 RELEASE-SHA256SUMS.txt
```

---

## 安装包内含进程

| 文件 | 作用 |
|------|------|
| `browboxs-desktop` | **唯一产品 UI 入口** |
| `browboxs-agent` | 本机 Local API · 环境 · 内核 · RPA 执行 |
| `browboxs-server` | 可选：本机节点主机 · 子账号 · 权限 |

---

## 源代码

- 本公开仓：**pack 脚本 + 安装产物**，默认 **不**提供完整业务 monorepo。  
- 从 kit 组装：`scripts/pack-kit-to-release.sh`。  
- 完整编译：需 core 私有仓权限（见上游 BUILD-FROM-SOURCE）。

---

## 发布渠道

| 渠道 | 说明 |
|------|------|
| **GitHub Release（正式）** | 唯一官方安装文件来源 |
| kits-v* prerelease | 私有 CI 中转的无源码 kit（非最终用户包） |

请认准仓库 owner，谨防仿冒。

---

## 热更新（各安装类型 → 自己的源）

所有安装形态（tree / portable / deb / AppImage / NSIS / DMG）装好后，**模块热更新只走本仓库的 tree 资产**，不走第三方源：

| 安装类型 | 安装资产示例 | 热更新脚本 | 更新源 | 下载资产 |
|----------|--------------|------------|--------|----------|
| tree | `browboxs-<ver>-linux-x86_64.tar.gz` | `scripts/update-modules.sh` | **本仓** `wpmmcc/browboxs-app-releases` | `browboxs-<ver>-<os>-<arch>.tar.gz` |
| portable | `…-portable.zip` | 同上（包内同脚本） | **本仓** app-releases | 同上 tree tar（非 zip） |
| deb | `…-linux-x86_64.deb` | `/opt/browboxs/scripts/update-modules.sh` | **本仓** app-releases | 同上 tree tar |
| nsis / dmg | 系统安装器 | 安装树内同脚本 | **本仓** app-releases | 同上 tree tar |

```bash
# 检查更新（只读）
BROWBOX_INSTALL_ROOT=$HOME/.local/opt/browboxs \
  bash $BROWBOX_INSTALL_ROOT/scripts/update-modules.sh --check

# 应用热更新（下载 platform tree + 校验 sha256 + 覆盖 bin/modules/ui/scripts）
BROWBOX_INSTALL_ROOT=$HOME/.local/opt/browboxs \
  bash $BROWBOX_INSTALL_ROOT/scripts/update-modules.sh
```

包内 `modules/manifest.json` 的 `github` / `github_app` 指向 **app-releases**；`github_engines` 指向 **engines-releases**（指纹引擎独立频道，不与 app 混下）。  
`modules/INSTALL_TYPE` · `modules/UPDATE_SOURCE.txt` 标明本包安装形态与更新源约定。
