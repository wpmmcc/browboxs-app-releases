# browboxs-app-releases（公开 · 安装包 / pack / 更新）

| 内容 | 说明 |
|------|------|
| GitHub Releases | 用户安装包（多格式）+ `RELEASE-SHA256SUMS.txt` |
| `INSTALL.md` | **按 OS 拆分的安装说明与系统要求**（Clash Verge 风格） |
| `scripts/pack-kit-to-release.sh` | kit → 用户资产（**不**编译核心源码） |
| `.github/workflows/pack-and-test.yml` | **每平台×架构一 runner** free-runner 矩阵 |
| prerelease `kits-v*` | 私有 core 上传的无源码 kit 中转 |

## 禁止

- 完整 monorepo / `crates/` 业务源码  
- 生产密钥  
- 在 public runner 上 `cargo build -p browboxs-client-agent`

## 同步（从私有 core monorepo）

```bash
# 在 core monorepo 根：
bash scripts/sync-to-public-releases.sh --all --version 0.1.0
```

## 打包类型

见 `docs/PACKAGING-TYPES-AND-COMPAT.md`（与 monorepo 同源）。

| 平台 | P0 形态 | Runner |
|------|---------|--------|
| Linux x64 | tar + deb + AppImage | ubuntu-22.04 |
| Linux arm64 | tar + deb + AppImage | ubuntu-24.04-arm |
| Windows x64 | tar + portable（+ nsis 有工具时） | windows-latest |
| macOS arm64 | tar（+ dmg 有工具时） | macos-latest |
| macOS x64 | tar | macos-latest |

## 安装

见 [INSTALL.md](./INSTALL.md)。

## 公开 Runner 测试（找问题）

`pack-and-test` 在 **每平台原生 runner** 上：

1. 下载 **无源码 binary kit**（禁止 kit 内含 `crates/` / `Cargo.toml`）
2. `pack-kit-to-release` 注入 `update-modules` + own-source manifest → tree/portable/deb…
3. **`public-runner-product-smoke.sh`**：
   - 包结构 / 无源码泄露
   - agent health · 鉴权 401/Bearer
   - **UI 对应 API 矩阵**（profiles / proxies / workflows / cookies / fingerprint / updates…）
   - 根路径禁止 SPA 控制台
   - 更新源 = 本仓 tree；引擎源分离
   - Linux：portable + deb 各再跑一轮 smoke
   - 可选 `browboxs-desktop` + xvfb

核心业务只以 **二进制** 参与公开打包；完整源码仅私有 monorepo。

