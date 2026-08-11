# 正式发布主链路（MAIN · 已验证冻结）

> **状态**：2026-08-12 **架构确认**（**本机交叉出 kit** + 公开 pack/install 全矩阵已绿；**私有仓 Actions 已关**）  
> **SoT 关系**：本文件描述 **main 默认流程**；细节见  
> [`PACKAGING-HYBRID-PRIVATE-PUBLIC.md`](./PACKAGING-HYBRID-PRIVATE-PUBLIC.md) ·  
> [`PACKAGING-TYPES-AND-COMPAT.md`](./PACKAGING-TYPES-AND-COMPAT.md) ·  
> [`PACKAGING-ARCHITECTURE.md`](./PACKAGING-ARCHITECTURE.md)

---

## 0. 一句话

```text
[本机 monorepo] Rust 交叉编译 → 无源码 kit（无私有 GH runner）
    → [公开 main] pack 开源侧脚本/安装器 + 注入 UI 静态与更新源
    → 安装测试（真实用户路径）
    → 安装后 UI/功能测试（API 矩阵 + 可选 desktop/有头）
    → 用户 GitHub Release
```

| 层 | 仓 / 分支 | 做什么 | 不做什么 |
|----|-----------|--------|----------|
| **S0 Kit** | **本机**（私有 monorepo 检出）· `scripts/host-cross-kits.sh` / `make-kit.sh` | 本机 Rust **交叉编译** agent/server → harden → `kit-<os>-<arch>.tar.gz` 上传公开 prerelease `kits-v*` | **私有仓 GitHub Actions 已关闭**；禁止再在 private 上跑 prepare-kits/release runner |
| **S1 Pack** | 公开 `browboxs-app-releases` **`main`** · `pack-and-test` | 消费 kit；`pack-kit-to-release` 组合 **可开源内容**（scripts / INSTALL / update-modules / manifest 通道） | **禁止** `cargo build` 核心 crates |
| **S2 Install** | 同 workflow `install-from-release` | 从 **正式 `v*` Release** 下载用户包 → 解压/`install-system` → 结构断言 | 不测 monorepo checkout |
| **S3 UI/功能** | 同 runner 上 `product-smoke` +（扩展）UI 功能门禁 | 安装根上：鉴权、工作台依赖 API、更新 own-source；Linux xvfb desktop；有头点击 lab 另轨 | 不在公开仓编译 React 业务源（UI dist 已在 kit） |

**废弃 / 禁止**：

- 私有仓 `prepare-kits` / `release` / `ci` 等 **GitHub-hosted runner 编译**（workflow 已删，Actions `enabled=false`）。  
- 公开 main 长期只吃「旧 kit / 仅 linux-x86_64」——有本机出的多平台 kit 则全量 pack。  
- 宿主新 glibc 的 linux-x64 直接当正式包——正式优先 **`host-cross-kits.sh --docker-glibc22`**。  
- `test/cross-pack-*` 当长期发版分支——以 **public main** 为准。

---

## 1. Kit 来源策略（确认）

### 1.1 正式默认（MAIN）— **本机交叉，无私有 runner**

| 平台 | 产出方式 | triple | 说明 |
|------|----------|--------|------|
| linux-x86_64 | 本机或 **`host-cross-kits.sh --docker-glibc22`** | `x86_64-unknown-linux-gnu` | 正式用户包优先 Docker 22.04 编（GLIBC ≤ 2.34） |
| linux-aarch64 | 本机 cross（`gcc-aarch64-linux-gnu`） | `aarch64-unknown-linux-gnu` | host-cross 默认 |
| windows-x86_64 | 本机 cross **mingw-gnu** | `x86_64-pc-windows-gnu` | host-cross 默认；非 msvc |
| windows-aarch64 | **仅 Windows ARM 本机** | `aarch64-pc-windows-msvc` | Linux 宿主无法交叉 |
| darwin-aarch64 / x86_64 | **仅 macOS 本机** | `*-apple-darwin` | Linux 宿主无法交叉 |

产出名：`kit-linux-x86_64.tar.gz` …（有本机才有对应 kit）  
中转：公开仓 **prerelease** `kits-v<ver>`。

```bash
# 本机一次出可交叉平台 kit 并上传 + 触发公开 pack
BROWBOX_VERSION=0.2.5 bash scripts/host-cross-kits.sh --docker-glibc22 --publish --dispatch
```

### 1.2 已废弃：私有 GitHub `prepare-kits` runner

| 项 | 状态 |
|----|------|
| private `prepare-kits.yml` / `release.yml` / `ci.yml` | **已删除**；仓库 Actions **enabled=false** |
| 私有仓 hosted / self-hosted runner 编译 | **禁止再启用**（除非业主明确改决策） |
| 公开 `pack-and-test` free runners | **保留**（只 pack + 安装测，不编核心） |

### 1.3 Kit 内与「可开源组合」边界

```text
kit（私有产出，无业务源码）
  bin/browboxs-agent[.exe]
  bin/browboxs-server[.exe]
  bin/browboxs-desktop[.exe]   # 正式包应含；slim 可缺
  ui/desktop/                  # 静态 dist（私有 npm build 写入）
  modules/manifest.json 骨架
  PLATFORM.txt VERSION TRIPLE.txt …

公开 pack 注入 / 组合（app-releases 仓内开源）
  scripts/update-modules.sh · install-system.sh · verify-*
  INSTALL.md · 文档
  packaging 规范化：own-source github_app / install_types
  → browboxs-<ver>-<os>-<arch>.{tar.gz,deb,portable…}
```

---

## 2. MAIN 分支日常命令（正常流程）

### 2.1 本机 monorepo（S0 · 唯一 kit 源）

```bash
# 交叉可出的平台 + 可选 22.04 docker 出 linux-x64 + 上传 + 触发公开 pack
BROWBOX_VERSION=0.2.5 bash scripts/host-cross-kits.sh --docker-glibc22 --publish --dispatch

# 仅当前 OS 单 kit：
BROWBOX_VERSION=0.2.5 bash scripts/make-kit.sh
bash scripts/publish-kit-to-public.sh --version 0.2.5 --dispatch
```

**不要**再对 `wpmmcc/browboxs-v2-private` 执行任何 `gh workflow run`（Actions 已关、YAML 已删）。

### 2.2 公开 app-releases `main`

```bash
# 仅重打包装包（kit 已在 kits-v*）
gh workflow run pack-and-test.yml -R wpmmcc/browboxs-app-releases --ref main \
  -f version=0.2.5 -f kit_tag=kits-v0.2.5 -f publish=true -f allow_partial=false
```

### 2.3 从 monorepo 同步公开脚本（始终推 **main**）

```bash
# monorepo 根；镜像源 packaging/public-app-releases/
bash scripts/sync-to-public-releases.sh --push-scripts --version 0.2.5
# 或本机已有 kit：
bash scripts/sync-to-public-releases.sh --all --version 0.2.5
```

`sync-to-public-releases.sh` 目标默认 **`origin/main`**（见脚本），不再依赖 `test/cross-pack-*`。

### 2.4 mac / win-arm（需对应本机）

Linux 宿主 **不能** 交叉出 darwin / windows-aarch64。若要这些 kit：在对应机器上跑 `make-kit.sh` 后 `publish-kit-to-public.sh` 上传到同一 `kits-v*`，再触发公开 pack（`allow_partial` 可先 true）。
---

## 3. 测试四级（与 workflow 对齐）

| 级 | 名称 | 何时 | 工具 | 失败策略 |
|----|------|------|------|----------|
| **T0** | Kit 边界 | prepare-kits / pack 下载后 | 禁 crates/Cargo.toml；sha256 | **硬失败** |
| **T1** | Pack smoke | pack 后 tree（+ portable/deb） | `public-runner-product-smoke.sh` | 结构/源码泄露硬失败；API/鉴权 soft 可 WARN |
| **T2** | Install-from-release | publish 后 | 下载 `v*` 用户包 → 安装根 → 再 smoke | 缺包（optional 平台）可 skip；agent/server 必须 PASS |
| **T3** | UI/功能 | 安装根上 | **默认**：UI 依赖 API 矩阵（profiles/proxies/workflows/cookies/fingerprint/updates）+ 更新 own-source；**Linux**：desktop xvfb 进程；**有头点击**：lab / 自托管（`tests/e2e_headed_product.sh`、workbench mjs） | CI free runner 默认 T3-API；T3-headed 不阻塞 main 发版除非显式开启 |

**产品入口**：`browboxs-desktop`；Agent 默认不 SERVE_UI。T3 不以「浏览器打开 Local API」为通过标准。

---

## 4. 平台矩阵（main 冻结）

| platform_key | kit 名 | pack runner | 用户资产前缀 | P |
|--------------|--------|-------------|--------------|---|
| linux-x86_64 | kit-linux-x86_64 | ubuntu-22.04 | browboxs-*-linux-x86_64 | P0 |
| linux-aarch64 | kit-linux-aarch64 | ubuntu-24.04-arm | …-linux-aarch64 | P0 |
| windows-x86_64 | kit-windows-x86_64 | windows-latest | …-windows-x86_64 | P0 |
| windows-aarch64 | kit-windows-aarch64 | windows-11-arm | …-windows-aarch64 | P1 |
| macos-aarch64 | kit-darwin-aarch64 | macos-latest | …-macos-aarch64 | P0 |
| macos-x86_64 | kit-darwin-x86_64 | macos-latest | …-macos-x86_64 | P1 |

---

## 5. 相对旧 main 的调整清单

| 项 | 旧（test 前 / 旧 main） | 现（确认 MAIN） |
|----|------------------------|-----------------|
| kit 来源 | 常仅 linux-x86 / 旧 tag | `prepare-kits` 六 cell → `kits-v*` |
| 公开默认分支 | 脚本推 HEAD；试验在 `test/cross-pack-*` | **`main`** 承载 pack-and-test + install 矩阵 |
| smoke 鉴权 | unauth 非 401 红 portable/deb | 401/403 OK；200 WARN；SOFT 不挡 pack |
| mac bash | eval+heredoc | env 文件 source；无 xargs -r |
| win-arm | 无 | prepare-kits + pack + install-from-release |
| install 测试 | 部分/无 | 全矩阵 `install-from-release` |
| UI 测试 | 仅 API 夹在 smoke | **显式 S3 阶段**（API 默认；headed lab 扩展） |

---

## 6. 发版检查单（main）

1. [ ] 本机 `host-cross-kits.sh` / `make-kit` 产出目标 kit 并上传 `kits-v*`（私有 Actions 保持关闭）  
2. [ ] 公开 `kits-v<ver>` 含目标平台 kit + sha256  
3. [ ] 公开 `main`：`pack-and-test` 全绿（pack + publish + install-from-release）  
4. [ ] `v<ver>` Release 资产与 `RELEASE-SHA256SUMS.txt` 齐全  
5. [ ] 至少一平台人工：安装 → 开 desktop → 侧栏点通（T3-headed / lab）  
6. [ ] 热更：`update-modules --check` 指向 **本仓** tree，非错平台/portable  

---

## 7. 相关入口

| 路径 | 角色 |
|------|------|
| 私有 `.github/workflows/prepare-kits.yml` | S0 |
| 公开 `.github/workflows/pack-and-test.yml` | S1–S3 |
| `scripts/make-kit.sh` · `publish-kit-to-public.sh` | 本地/CI kit |
| `scripts/sync-to-public-releases.sh` | 同步公开 **main** 脚本 |
| `scripts/public-runner-product-smoke.sh` | T1/T2/T3-API |
| `scripts/public-runner-ui-function-smoke.sh` | T3 显式 UI/功能（薄封装） |
| `tests/e2e_headed_product.sh` | T3-headed（lab/自托管） |
