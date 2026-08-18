# macOS Tauri WebView 自动化（装机 / CI）

> **结论（已落地）：** macOS 无法走 `tauri-driver + WebKitWebDriver`（Apple 不给 WKWebView 系统级 driver）。  
> **深入测试**必须在 release 二进制中编入 **`tauri-plugin-wdio-webdriver`**（feature `wdio-e2e`），通过 **`TAURI_WEBDRIVER_PORT`** 启动内嵌 W3C WebDriver，再跑与 Linux 同源的 `full_workbench_installed.py`。

---

## 方案对比（为何改二进制）

| 方案 | 不改二进制能否深入 WebView 点测 | 说明 |
|------|--------------------------------|------|
| 官方 `tauri-driver` 直连 | ❌ | mac 无 WKWebView native driver |
| CrabNebula | ✅ | 需 `CN_API_KEY`；测未改 release 包 |
| **Embedded `tauri-plugin-wdio-webdriver`** | ❌（需编译进包） | **本仓库选用**；与 Linux 同一套 full workbench 脚本 |

不改二进制只能做 **S3a API 矩阵 + 进程 smoke**，无法点击侧栏、填表、校验 WebView 与 API 双断言。

---

## 平台对照（当前 S3b）

| 平台 | Driver 模式 | 门禁 |
|------|-------------|------|
| **Linux** | `external`：`tauri-driver` + `WebKitWebDriver` | **硬门禁** |
| **Windows** | `external`：`tauri-driver` + `msedgedriver` | 默认 soft（`STRICT=0`） |
| **macOS aarch64** | **`embedded`** | **硬门禁**（原生 ARM） |
| **macOS x86_64** | **`embedded`** | **非硬门禁**：GitHub `macos-latest` 为 ARM，x86_64 走 Rosetta；WKWebView `execute/sync` 会 script timeout。原生 Intel 机仍可 STRICT=1 |

Pack 阶段：

- **macOS**：`BROWBOX_DESKTOP_WDIO=1` → `tauri build --features wdio-e2e`
- **Linux / Windows**：不编入插件（走外部 `tauri-driver`）

运行时仅当设置 `TAURI_WEBDRIVER_PORT` 时才 `init()` 插件。上游 `init()` 在环境变量未设时仍会监听 **4445**，会与 Linux `WebKitWebDriver` 抢端口，因此必须这层门闩。

---

## 实现要点

| 组件 | 位置 |
|------|------|
| Feature + 依赖 | `desktop-shell/src-tauri/Cargo.toml` → `wdio-e2e` |
| 插件注册 | `lib.rs` → `#[cfg(feature = "wdio-e2e")] builder.plugin(...)` |
| 权限 | `capabilities/default.json` → `wdio-webdriver:default` |
| Pack | `scripts/build-desktop-from-kit.sh` |
| 测试 | `scripts/e2e-tauri/full_workbench_installed.py`（`BROWBOX_E2E_DRIVER=embedded`） |
| Runner | `scripts/public-runner-tauri-ui-e2e.sh` |

### macOS CI 环境变量

```bash
export BROWBOX_E2E_DRIVER=embedded
export TAURI_WEBDRIVER_PORT=4445
export BROWBOX_E2E_KEEP_SPLASH=1
export BROWBOX_TAURI_E2E_STRICT=1
python3 scripts/e2e-tauri/full_workbench_installed.py
```

---

## Pipeline 布局

```text
S3a  product-smoke     → API 矩阵（全平台）
S3b  tauri WebView     → full_workbench_installed.py
                       → Linux/Win external · macOS embedded
S3c  Playwright 静态页 → lab，非产品门
```

**Full workbench 覆盖：**

- 侧栏 **全部 nav** 模块点击 + 页面关键词
- **新建环境**：填名、点创建、API 校验 profiles
- **代理 / 引擎 / 工作流 / 任务** API 双断言

---

## 安全说明

- `wdio-e2e` 仅用于 **public runner 编译的安装包**；插件仅在 `TAURI_WEBDRIVER_PORT` 设置时暴露 loopback WebDriver。
- 若需「用户同款、零插件」的 mac 深度测试，可另开 CrabNebula 路径（`CN_API_KEY`），与本 embedded 路径二选一或并行。

---

## 本机 Linux full workbench

```bash
export BROWBOX_PREFIX="$HOME/.local/opt/browboxs-lab"
export BROWBOX_DESKTOP="$BROWBOX_PREFIX/bin/browboxs-desktop"
export BROWBOX_E2E_KEEP_SPLASH=1
cargo install tauri-driver --locked
# apt install webkit2gtk-driver xvfb
python3 scripts/e2e-tauri/full_workbench_installed.py
```
