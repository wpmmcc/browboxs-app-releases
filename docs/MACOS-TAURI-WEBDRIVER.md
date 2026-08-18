# macOS Tauri WebView 自动化（装机 / CI）

> 结论：**不能**在 macOS 上直接用 `tauri-driver + WebKitWebDriver`（Linux 那条路）。  
> Apple **没有**给嵌入式 WKWebView 提供系统级 WebDriver；`safaridriver` 只驱动 Safari 浏览器本身。

---

## 平台对照

| 平台 | 外部 native driver | 本仓库 S3b 现状 |
|------|-------------------|-----------------|
| **Linux** | `WebKitWebDriver`（`webkit2gtk-driver`）+ `tauri-driver` | **硬门禁**：`full_workbench_installed.py` 全侧栏 + 创建环境 + API 双断言 |
| **Windows** | `msedgedriver` + `tauri-driver` | 跑 full workbench，默认 non-strict |
| **macOS** | **无** Apple 官方 WKWebView driver | **跳过** WebView 点测；仅 S3a API + 进程 smoke |

官方说明：[Tauri WebDriver manual setup](https://v2.tauri.app/develop/tests/webdriver/manual-setup/) — *direct tauri-driver: macOS has no WKWebView driver tool available*。

---

## macOS 上「应该有什么」（按推荐顺序）

### 1. 官方推荐：`@wdio/tauri-service` + **embedded** WebDriver（首选）

应用内嵌 W3C WebDriver HTTP 服务，**不依赖**外部 `tauri-driver`：

| 组件 | 包 | 作用 |
|------|-----|------|
| Rust 内嵌 server | `tauri-plugin-wdio-webdriver` | 应用内 HTTP WebDriver（WKWebView 原生 API） |
| 进阶 IPC/日志 | `tauri-plugin-wdio` + `@wdio/tauri-plugin` | `browser.tauri.execute()`、mock、日志 |
| 测试 runner | `@wdio/tauri-service` | `driverProvider: 'embedded'`（mac 默认） |

文档：[WebdriverIO Tauri plugin setup](https://webdriver.io/docs/desktop-testing/tauri/plugin-setup/)

**要点：**

- 插件应 **`#[cfg(debug_assertions)]` 或 feature 门控**，不要打进普通 release（安全面）。
- 服务通过环境变量 **`TAURI_WEBDRIVER_PORT`** 启动内嵌 server；正常用户不设置则不应监听。
- 对 **公开 runner 已发布的 release 包**：当前 **未** 编入 embedded 插件 → **无法** 对「用户同款二进制」做 WebView 点测。
- 若要 mac CI 硬门禁：需在 `desktop-shell` 增加 `wdio-e2e` feature，**仅 mac pack** 时 `tauri build --features wdio-e2e`，并接 `@wdio/tauri-service`。

### 2. 商业：CrabNebula WebDriver

- 跨平台外部 driver fork，**mac 需 API key**（`CN_API_KEY`）。
- 适合测 **未改二进制** 的 release 安装包。
- 文档：[CrabNebula setup](https://webdriver.io/docs/desktop-testing/tauri/crabnebula-setup/)

### 3. 社区

| 项目 | 说明 |
|------|------|
| [danielraffel/tauri-webdriver](https://danielraffel.me/2026/02/14/i-built-a-webdriver-for-wkwebview-tauri-apps-on-macos/) | WKWebView W3C driver；需 app 内 debug plugin + CLI `tauri-wd` |
| [tauri-pilot](https://github.com/foxycode-dev/tauri-pilot) | LLM/调试向，非装机门禁 |
| [mcp-tauri-automation](https://github.com/danielraffel/mcp-tauri-automation) | MCP + WebDriver，偏 mac 开发期 |

---

## 与本仓库 public runner 的关系

```text
S3a  product-smoke     → API 矩阵（全平台）
S3b  tauri WebView     → Linux full workbench（硬）
                       → Windows full workbench（软）
                       → macOS skip（待 embedded 或 CrabNebula）
S3c  Playwright 静态页 → lab，非产品门
```

**Linux full workbench 覆盖**（`scripts/e2e-tauri/full_workbench_installed.py`）：

- 侧栏 **全部 nav** 模块点击 + 页面关键词
- **新建环境**：填名、点创建、API 校验 profiles
- **代理 / 引擎 / 工作流 / 任务** API 双断言
- 非「点两下设置就绿」

---

## 下一步接 mac（待选方案）

**A. Embedded（与 Linux 同源测试脚本，改 WDIO 配置）**

1. `desktop-shell` 加 optional feature `wdio-e2e` → `tauri-plugin-wdio-webdriver`
2. macOS pack job：`BROWBOX_DESKTOP_WDIO=1 tauri build --features wdio-e2e`
3. `install-from-release` mac：`@wdio/tauri-service` embedded + 移植 full workbench 为 WDIO spec
4. Release 包是否含 plugin：仅当 `TAURI_WEBDRIVER_PORT` 未设置时不监听（需安全评审）

**B. CrabNebula（不改产品二进制）**

1. 仓库 secret `CN_API_KEY`
2. mac job：`driverProvider: 'crabnebula'`
3. 同一 full workbench 逻辑

**C. 维持 mac skip + 本机/签后人工**

- Linux 硬门禁 + S3a API 覆盖 mac 同款 agent/server/ui dist

---

## 命令（本机 Linux full workbench）

```bash
export BROWBOX_PREFIX="$HOME/.local/opt/browboxs-lab"
export BROWBOX_DESKTOP="$BROWBOX_PREFIX/bin/browboxs-desktop"
export BROWBOX_E2E_KEEP_SPLASH=1
cargo install tauri-driver --locked
# apt install webkit2gtk-driver xvfb
bash apps/desktop/e2e-tauri/run-full-workbench.sh
# 或
python3 scripts/e2e-tauri/full_workbench_installed.py
```
