# MotionControl 分支策略

> **本文件记录项目的双发布版本分支管理策略**

---

## 一、双版本说明

MotionControl 有两个发布版本，分别面向不同的用户群体：

### 1.1 GitHub 公开发布版（`main` 分支）
- **目标用户**：技术用户、开源贡献者、DMG 直接下载者
- **发布方式**：GitHub Releases + DMG 镜像
- **签名要求**：Developer ID Application (DMG 公证)
- **沙盒**：**无沙盒**（DMG/官网分发不需要沙盒）
- **打包命令**：`./build-dmg.sh`（项目自带脚本）
- **核心优势**：
  - 用户无需 App Store 账号
  - 可以直接下载安装
  - 完整的辅助功能权限（系统级）

### 1.2 App Store 上架版（`appstore` 分支）
- **目标用户**：普通 macOS 用户、App Store 下载者
- **发布方式**：App Store Connect + PKG 安装包
- **签名要求**：Mac App Distribution + 3rd Party Mac Developer Installer
- **沙盒**：**有沙盒**（App Store 硬性要求）
- **打包命令**：`bash scripts/build_pkg.sh`
- **核心优势**：
  - App Store 审核保证（代码质量、隐私）
  - 自动更新（用户无感知）
  - 用户信任度高

---

## 二、分支关系图

```
┌─────────────────────────────────────────────────────────────┐
│                       feat/* (开发分支)                       │
│  feat/frame-loss-guard, feat/jitter-suppression, etc.        │
└─────────────────────────┬───────────────────────────────────┘
                          │ 合并
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                        main 分支                              │
│            GitHub 公开发布版（无沙盒，DMG）                   │
│                                                                │
│  - XPC Service (开发中)                                       │
│  - 完整辅助功能（无沙盒限制）                                 │
│  - 任意 PID 扫描                                              │
└─────────────────────────┬───────────────────────────────────┘
                          │ Cherry-pick / 移植
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              fix/ax-scan-sandbox-click                       │
│            AX 扫描沙盒兼容性修复（独立 PR）                  │
│                                                                │
│  - UNIX Socket + 独立 AXHelper 进程                          │
│  - 沙盒内能用 AX 扫描                                         │
│  - 通过 PKG 沙盒分支发布                                      │
└─────────────────────────┬───────────────────────────────────┘
                          │ 合并
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      appstore 分支                           │
│            App Store 上架版（沙盒，PKG）                       │
│                                                                │
│  - 在 main 基础上加沙盒 entitlements                         │
│  - 内嵌 AXHelper（无沙盒）                                    │
│  - PKG postinstall 注册 LaunchAgent                           │
│  - socket 路径在沙盒容器内                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、分支对应关系

| GitHub 版 | App Store 版 | 差异 |
|-----------|-------------|------|
| `main` | `appstore` | entitlements（沙盒）、签名（Mac App Distribution）、包格式（DMG vs PKG）、代码（主 App 走 XPC，沙盒版走 UNIX Socket） |
| `main` | `fix/ax-scan-sandbox-click` | 沙盒 + AX 扫描修复（独立 PR，合并到 appstore） |
| `appstore` | — | 上架版（v0.8.3 之后没更新） |
| `feat/*` | — | 实验性功能 |

---

## 四、版本号管理

| 发布版 | 版本号 | 状态 |
|--------|--------|------|
| GitHub 版 v0.1.0 | 已发布 | `main` |
| App Store 版 v0.8.3 | 已上架 | `appstore`（修复前） |
| App Store 版 v0.9.0 | 待上架 | `fix/ax-scan-sandbox-click` → 合并到 `appstore` |

**版本号规则**：
- 同一功能同时在两个版本发布 → 两边同步版本号
- 仅 GitHub 版功能 → 只在 `main` 升版本
- 仅 App Store 修复 → 在 `appstore` 上打 patch 号（如 0.8.3 → 0.8.4）

---

## 五、合并与发布流程

### 5.1 `main` → `appstore`（常规）
1. 在 `main` 上完成开发
2. Cherry-pick 到 `appstore`（或 rebase）
3. 加沙盒 entitlements（`build/Entitlements.plist`）
4. 用 `scripts/build_pkg.sh` 打包
5. 提交到 App Store Connect

### 5.2 `main` → `appstore`（修复，特殊情况）
1. 在独立分支修复（如 `fix/ax-scan-sandbox-click`）
2. 同时 cherry-pick 到 `main` 和 `appstore`（如果修复也适用于 GitHub 版）
3. 验证两个版本都正常
4. 删除修复分支（或保留作为历史记录）

---

## 六、代码差异点

### 6.1 `main` 分支独有
- `Sources/AXHelper/` 完整代码（XPC Service 版本）
- DMG 打包脚本 `build-dmg.sh`
- 完整 GitHub 文档（README.md 等）

### 6.2 `appstore` 分支独有
- 沙盒 entitlements 文件
- PKG 打包脚本 `scripts/build_pkg.sh`
- AX_SCAN_FIX.md（修复文档）
- 沙盒适配的 UI 代码（权限申请引导）

### 6.3 共享代码
- 核心 MotionControl 功能
- 检测算法
- UI 组件

---

## 七、关键文件

| 文件 | `main` | `appstore` |
|------|:------:|:----------:|
| `Sources/AXHelper/main.swift` | XPC Service | UNIX Socket |
| `Sources/MotionControl/Info.plist` | 公开版 | 加 LSApplicationCategoryType |
| `build/Entitlements.plist` | 不需要 | app-sandbox=true |
| `build/Entitlements-NoSandbox.plist` | 不需要 | 空（AXHelper） |
| `scripts/build_pkg.sh` | 不需要 | 需要 |
| `build-dmg.sh` | 需要 | 不需要 |
| `AX_SCAN_FIX.md` | 不需要 | 需要 |

---

## 八、PR 流程

### 8.1 普通功能开发
```
feat/* → main → 评估是否需要同步到 appstore
```

### 8.2 沙盒修复
```
fix/ax-scan-sandbox-click → main (可选) → appstore
```

### 8.3 紧急修复（hotfix）
直接在 main 上提交 → cherry-pick 到 appstore

---

## 九、CI/CD 建议

未来可以加：
- `.github/workflows/release-github.yml` — 推送 tag → 自动 build DMG → 发 GitHub Release
- `.github/workflows/release-appstore.yml` — 推送 tag → 自动 build PKG → 上传 App Store Connect

---

**详细修复内容见 [AX_SCAN_FIX.md](./AX_SCAN_FIX.md)**
