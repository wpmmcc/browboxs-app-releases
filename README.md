# browboxs-app-releases（公开 · MAIN 安装包 / pack / 更新）

> **正式分支：`main`**。验证分支 `test/cross-pack-*` 仅试验，合入后以 main 为准。  
> 全链路 SoT：`docs/RELEASE-MAIN-PIPELINE.md`

| 内容 | 说明 |
|------|------|
| GitHub Releases `v*` | 用户安装包（多格式）+ `RELEASE-SHA256SUMS.txt` |
| prerelease `kits-v*` | 私有 core 上传的 **无源码** kit 中转 |
| `INSTALL.md` | 按 OS 安装说明与系统要求（Clash Verge 风格） |
| `scripts/pack-kit-to-release.sh` | kit → 用户资产（**不**编译核心源码） |
| `scripts/public-runner-product-smoke.sh` | 包结构 + API + 更新源 |
| `scripts/public-runner-ui-function-smoke.sh` | **S3a** 安装后 UI-API 功能门禁 |
| `scripts/public-runner-desktop-ui-e2e.sh` | **S3b** Playwright **有头**侧栏点击 + 可选 desktop xvfb |
| `scripts/ui-e2e/` | Playwright workbench e2e（无 monorepo） |
| `.github/workflows/pack-and-test.yml` | S1 pack → publish → S2 install → S3 UI |

## 禁止

- 完整 monorepo / `crates/` 业务源码  
- 生产密钥  
- 在 public runner 上 `cargo build` 核心 crates  

## MAIN 流程

```text
私有 prepare-kits (main) → kits-v* → 公开 pack-and-test (main)
  → pack + product-smoke
  → publish v*
  → install-from-release
  → S3a UI-API smoke
  → S3b headed Playwright UI e2e
```

```bash
# 从私有 monorepo 同步脚本到本仓 main：
bash scripts/sync-to-public-releases.sh --push-scripts --version 0.2.5

# 重跑 pack（kit 已存在）：
gh workflow run pack-and-test.yml -R wpmmcc/browboxs-app-releases --ref main \
  -f version=0.2.5 -f kit_tag=kits-v0.2.5 -f publish=true
```

## 矩阵

| 平台 | kit | runner |
|------|-----|--------|
| Linux x64 | kit-linux-x86_64 | ubuntu-22.04 |
| Linux arm64 | kit-linux-aarch64 | ubuntu-24.04-arm |
| Windows x64 | kit-windows-x86_64 | windows-latest |
| Windows arm64 | kit-windows-aarch64 | windows-11-arm |
| macOS arm64 | kit-darwin-aarch64 | macos-latest |
| macOS x64 | kit-darwin-x86_64 | macos-latest |

## 安装

见 [INSTALL.md](./INSTALL.md)。架构细节见 [docs/RELEASE-MAIN-PIPELINE.md](./docs/RELEASE-MAIN-PIPELINE.md)。
