# 正式发布主链路（MAIN · 已验证冻结）

> **状态**：2026-08-12 **架构确认**（本机交叉 / 私有原生 kit + 公开 pack/install 全矩阵已绿）  
> **SoT 关系**：本文件描述 **main 默认流程**；细节见  
> [`PACKAGING-HYBRID-PRIVATE-PUBLIC.md`](./PACKAGING-HYBRID-PRIVATE-PUBLIC.md) ·  
> [`PACKAGING-TYPES-AND-COMPAT.md`](./PACKAGING-TYPES-AND-COMPAT.md) ·  
> [`PACKAGING-ARCHITECTURE.md`](./PACKAGING-ARCHITECTURE.md)

---

## 0. 一句话

```text
[私有] 多平台 Rust 核心二进制 → 无源码 kit
    → [公开 main] pack 开源侧脚本/安装器 + 注入 UI 静态与更新源
    → 安装测试（真实用户路径）
    → 安装后 UI/功能测试（API 矩阵 + 可选 desktop/有头）
    → 用户 GitHub Release
```

| 层 | 仓 / 分支 | 做什么 | 不做什么 |
|----|-----------|--------|----------|
| **S0 Kit** | 私有 `browboxs-v2-private` **`main`** · `prepare-kits.yml` | 每平台 **原生 runner** 编 agent/server/(desktop) → harden → `kit-<os>-<arch>.tar.gz` 上传公开 prerelease `kits-v*` | 不打 deb/nsis；不把 monorepo 源码推公开 |
| **S1 Pack** | 公开 `browboxs-app-releases` **`main`** · `pack-and-test` | 消费 kit；`pack-kit-to-release` 组合 **可开源内容**（scripts / INSTALL / update-modules / manifest 通道） | **禁止** `cargo build` 核心 crates |
| **S2 Install** | 同 workflow `install-from-release` | 从 **正式 `v*` Release** 下载用户包 → 解压/`install-system` → 结构断言 | 不测 monorepo checkout |
| **S3 UI/功能** | 同 runner 上 `product-smoke` +（扩展）UI 功能门禁 | 安装根上：鉴权、工作台依赖 API、更新 own-source；Linux xvfb desktop；有头点击 lab 另轨 | 不在公开仓编译 React 业务源（UI dist 已在 kit） |

**废弃 / 降级**（不再作为 main 默认）：

- 公开 main 长期只吃「旧 kit / 仅 linux-x86_64 单独编」——现已 **6 平台 kit 矩阵** 为默认。  
- 把 `test/cross-pack-*` 当长期发版分支——验证后 **合入 public main**。  
- 本机交叉编出的二进制直接当正式 linux-x64 用户包（**GLIBC 偏新**）——正式 **linux-x86_64 必须在 ubuntu-22.04 原生编**。

---

## 1. Kit 来源策略（确认）

### 1.1 正式默认（MAIN）

| 平台 | 产出位置 | triple / runner | 说明 |
|------|----------|-----------------|------|
| linux-x86_64 | 私有 prepare-kits | `ubuntu-22.04` · `x86_64-unknown-linux-gnu` | **GLIBC ≤ 2.34**，与 22.04 用户对齐 |
| linux-aarch64 | 私有 | `ubuntu-24.04-arm` | 原生 arm |
| windows-x86_64 | 私有 | `windows-latest` · msvc | 原生 |
| windows-aarch64 | 私有 | `windows-11-arm` · msvc | 原生（已验证） |
| darwin-aarch64 | 私有 | `macos-latest` | 原生 |
| darwin-x86_64 | 私有 | `macos-latest` cross-target | Apple 同机交叉 |

产出名：`kit-linux-x86_64.tar.gz` … `kit-windows-aarch64.tar.gz` · `kit-darwin-*.tar.gz`  
中转：公开仓 **prerelease** `kits-v<ver>`（仅二进制 + 布局，无 crates）。

### 1.2 辅助：本机 / 宿主机 Rust 交叉（可走通，非 main 默认）

| 场景 | 适用 | 限制 |
|------|------|------|
| 本机 `cargo` + rustup target | linux-x86_64 / linux-aarch64 / windows-gnu **快速试装** | 宿主 glibc 常 > 22.04 → 公开 22.04 **live smoke 需 soft**；**不可替代** 正式 22.04 kit |
| 本机交叉 darwin / win-arm | **不可靠**（无 Apple SDK / 无 arm MSVC） | 必须原生 runner |
| Docker `ubuntu:22.04` 编 x64 | 本机模拟正式 linux-x64 | 可作本地验收，正式仍以 CI prepare-kits 为准 |

辅助路径仍须：`make-kit` / `publish-kit-to-public` → 同一 `kits-v*` → **公开 main** `pack-and-test`。  
**不**在公开仓编 Rust 核心。

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

### 2.1 私有 core `main`

```bash
# 正式：六平台 kit（含 desktop 时 with_desktop=1）
gh workflow run prepare-kits.yml -R wpmmcc/browboxs-v2-private --ref main \
  -f version=0.2.5 -f with_desktop=1 -f dispatch_public=true
```

`prepare-kits` 成功后：上传 `kits-v0.2.5` → `repository_dispatch` / `workflow_dispatch` 触发公开 **main** `pack-and-test`。

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

### 2.4 本机交叉辅助（可选）

```bash
# 例：本机出 linux/win-gnu 试验 kit → 上传 → 公开 pack（allow_partial）
BROWBOX_VERSION=0.2.5-dev bash scripts/make-kit.sh   # 当前 OS/target
bash scripts/publish-kit-to-public.sh --version 0.2.5-dev --dispatch
```

正式发版 **不要** 用宿主 glibc 编的 linux-x64 覆盖 `kits-v*` 正式 tag。

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

1. [ ] 私有 `main`：`prepare-kits` 全绿（或 allow 的缺平台已声明）  
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
