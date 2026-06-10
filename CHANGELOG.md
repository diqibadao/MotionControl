# MotionControl 更新日志

---

## v0.7.2 (2026-06-10)

| 属性 | 内容 |
|------|------|
| **分支** | `feat/frame-loss-guard` |
| **基准** | `v0.7.1` |
| **作者** | Claude Fable 5 |

### 🐛 修复

**边缘粘连** — 去掉 edgeDamping 0.6，纯 clamp 裁剪
- 边缘死区 15.9% → 1.6%（-89.9%）
- 跳变、反转每帧率同时改善
- 业界标准：绝对映射不应对边缘单独降增益

**palmCenter 优化** — 中三指 MCP（index+middle+ring）均值，去 wrist+小指
- wrist 抖动 44.5px 拉偏中心，小指检测率最低 90.3%
- 方向一致性 X +5.5%、染色体对称性 +23.7%、抖动 -1.4px

**TCC 崩溃** — PermissionManager Speech 检查加 Bundle 判断，CLI 模式跳过

### ✨ 新功能

**日志自动落盘** — EventLogger 启动时自动创建 `Data/logs/raw/run_*.log`
- 线程安全（串行队列），每次 `log()` 同时写 stdout + 文件
- 分析管道：`analyze-cursor-log-v5.py --json` → `update-baseline.py` → `generate-report.py`

**PECF HTML 报告** — 静态 HTML，8 列统一格式（Baseline/当前/上次/目标/Δ最佳/Δ上次/判定）

### 🔧 改动文件

| 文件 | 改动 |
|------|------|
| `CursorController.swift` | 去 edgeDamping，纯 clamp |
| `HandPoseDetector.swift` | palmCenter 中三指 MCP 均值 |
| `EventLogger.swift` | startLogFile/stopLogFile，文件持久化 |
| `MotionControlApp.swift` | 日志启停生命周期 + KEYPOINTS 埋点 |
| `PermissionManager.swift` | Speech 检查 CLI 兼容 |
| `Package.swift` | DEBUG flag + Info.plist 嵌入 |
| `MotionControlTests.swift` | chirality 测试方向统一 |
| `scripts/analyze-cursor-log-v5.py` | --json 输出扩展（+frames/kp/l1/problems） |
| `scripts/update-baseline.py` | 🆕 自动更新基线，保留每项最优 |
| `scripts/generate-report.py` | 🆕 JSON→HTML 报告生成 |

### 📊 PECF

- J(P): 11🟢 / 0🔴，Pareto 改善通过
- 3328 帧实测，3 个历史问题全部消失

---

## v0.7.1 (2026-06-06)

| 属性 | 内容 |
|------|------|
| **分支** | `feat/frame-loss-guard` |
| **Commit** | (待提交) |
| **基准** | `v0.7.0` |
| **作者** | Claude Opus 4.8 |

### ✨ 新功能

**三区可变增益（Variable Absolute Mapping）** — 手近原点精控，手远自动 boost 触达全屏

- Interior（dist<0.12）：gain ×1.0，中心精控不变
- Border（0.12~0.25）：gain 线性 1.0→1.3，自然触达屏幕边缘
- Margin（>0.25）：gain 饱和 1.3，光标贴边不跳
- 回放验证：X 覆盖率 +10.4%（89%→100%），零额外跳变

**帧丢失保护（Temporal Gap Guard）** — UmeTrack (Meta SIGGRAPH 2022) 方案

- 检测帧间隔 >200ms → 用预测位置（上次目标 + 速度 × Δt）平滑过渡
- 300ms 二次 ease-in 从预测收敛到真实目标
- 历史 trace 验证：零帧丢失跳变

### 🐛 修复

**左手 chirality 方向反转** — 摄像头镜像 + `screenCX - offsetX` 对右手正确，左手 offsetX 需取反
**长时间退化** — `endCalibration()` 补全 gap guard 状态重置（prevUpdateTime/prevTarget/velocity）
**1€ Filter 首帧异常** — `reset()` 补上 `prevTime = 0`

### 🔧 改动文件

| 文件 | 改动 |
|------|------|
| `CursorController.swift` | 三区增益 + 左手 chirality + endCalibration 状态重置 + 1€ Filter prevTime |
| `MotionControlTests.swift` | 全 3 trace 回放 + chirality 测试方向更新 |

### 📊 指标变化（长测 vs v0.5.0）

| # | 指标 | v0.5.0 | v0.7.1 | 判定 |
|:--:|------|:--:|:--:|:--:|
| 8 | 抖动半径 | 11.8px | 5.3px | ✅ 减半 |
| 9 | 最大偏移 | 30.0px | 15.6px | ✅ 减半 |
| 23 | 帧丢失 | 2次 | 0次 | ✅ |

---

## v0.7.0 (2026-06-06)

| 属性 | 内容 |
|------|------|
| **分支** | `feat/unified-edge-handling` |
| **Commit** | `0fbee17` |
| **基准** | `v0.5.0-silky` |
| **作者** | Claude Opus 4.8 |

### ✨ 新功能

**离线回放测试框架** — 用历史手部轨迹测试当前算法，秒出 23 项指标

- `ReplayTest.replay(trace:)` — Swift 测试框架，调用真实 CursorController
- `swift test` — 自动回放 + 输出一致性报告 + 23 项指标
- 同一 trace → 不同版本 → 指标差异 = 纯算法差异

### 📊 数据资产

| 资产 | 说明 |
|------|------|
| 3 个版本轨迹 (trace.tsv) | 1616+1476+1813 帧 |
| 3 个版本元数据 (meta.yaml) | 参数配置 + 23 项指标 |
| 质量标准 v4.0 | 23 项编号指标 + 目标校准 |
| 指标历史记录 | 全版本追踪表 |
| 数据资产规划 | 离线回放/ML 训练路线图 |

### 🔧 改动文件

| 文件 | 改动 |
|------|------|
| `Tests/MotionControlTests.swift` | 新增回放测试框架 |
| `Docs/03-光标跟手质量标准.md` | v4.0 编号化 |
| `Docs/04-指标历史记录.md` | 全版本追踪 |
| `Docs/05-数据资产规划.md` | 回放/训练路线图 |
| `scripts/analyze-cursor-log.sh` | 23 项指标一键分析 |

---

## v0.6.1 (2026-06-06)

| 属性 | 内容 |
|------|------|
| **分支** | `feat/unified-edge-handling` |
| **Commit** | `213d366` |
| **基准** | `v0.5.0-silky` |
| **作者** | Claude Opus 4.8 |

### 🐛 修复

回退 v0.6.0 导致 11 项指标恶化的两个改动：
- 去三区 gainMultiplier（border 区增益放大 46-100%）
- 去 resetFilters()（帧丢失时重置滤波→制造跳变）

### 📊 效果（vs v0.5.0，135帧短测）

| # | 指标 | v0.5.0 | v0.6.1 | 变化 |
|:--:|------|:--:|:--:|:--:|
| 3 | 总滞后 | 197px | 144px | 变好 27% |
| 12 | 微步占比 | 77.9% | 88.8% | 变好 14% |
| 15 | 紧贴占比 | 49.9% | 77.6% | 变好 55% |
| 4 | 方向反转 | 5次 | 3次 | 变好 40% |
| 6 | 巨型跳变 | 5次 | 1次 | 变好 80% |
| 20 | 边缘死区 | 24.1% | 8.0% | 变好 67% |
| 22 | 方向错位 | 148次 | 2次 | 变好 99% |
| 23 | 帧丢失 | 2次 | 0次 | 变好 100% |

⚠️ 覆盖率(#18,#19)和抖动(#8,#9)需更长时间测试确认

### 🔧 改动文件

| 文件 | 改动 |
|------|------|
| `CursorController.swift` | 去三区增益 + 去边缘状态机 |
| `MotionControlApp.swift` | 去 resetFilters + lastFrameTime |

---

## v0.6.0 (2026-06-06)

| 属性 | 内容 |
|------|------|
| **分支** | `feat/unified-edge-handling` |
| **Commit** | `5a1fd25` |
| **Plan** | `.hermes/plans/23-统一边缘处理方案.md` |
| **基准** | `v0.5.0-silky` |
| **参考** | US Patent US20150177855A1 + US20020033799A1 + Meta UmeTrack |
| **作者** | Claude Opus 4.8 |

### 🏗️ 架构变更

**统一边缘处理：三区可变绝对映射 + 边缘反向解贴 + 帧丢失保护**

```
Interior (dist<0.12): gain=baseGain ×1.0   — 精控不变
Border (0.12~0.25):  gain 线性 ×1.0→×2.0  — 触达全屏
Margin (dist>0.25):  光标饱和贴边          — 不跳
边缘反向: 贴边时手反向→立即解贴, 死区→0
帧丢失: 间隔>200ms→重置滤波器, 不跳
```

### 🐛 修复

| 问题 | 根因 | 修复方式 |
|------|------|---------|
| 光标贴边拉不回来 | 绝对映射死区 13% 摄像头宽 | 三区增益 + 反向立即解贴 |
| 贴边时左右移只响应上下 | X 饱和后只响应 Y | 边缘方向检测 + 正交方向正常响应 |
| 偶尔跳变 | 帧丢失 1s 后滤波器累积偏移 | 间隔>200ms 重置滤波器 |

### 📊 质量标准

新增 I 类(边缘质量 4项) + J 类(性能 3项)，标准升至 v3.0

### 🔧 改动文件

| 文件 | 改动 |
|------|------|
| `CursorController.swift` | 三区增益 + 边缘状态机 + resetFilters() |
| `MotionControlApp.swift` | 帧间隔检测 + 滤波器重置 |
| `scripts/analyze-cursor-log.sh` | 新增 I/J 类 7 项指标 |
| `Docs/03-光标跟手质量标准.md` | 标准升至 v3.0 |

---

## v0.5.0 (2026-06-06)

| 属性 | 内容 |
|------|------|
| **分支** | `feat/jitter-suppression` |
| **Commit** | `1e3f832` |
| **Plan** | `.hermes/plans/22-抖动抑制-1e-filter调参.md` |
| **基准** | `v0.4.0-milestone` |
| **参考** | Casiez et al. CHI 2012 — 1€ Filter 标准调参流程 |
| **作者** | Claude Opus 4.8 |

### ⚡ 性能优化

| 参数 | 旧值 | 新值 | 理由 |
|------|:--:|:--:|------|
| 1€ Filter `fcMin` | 1.5 | 0.8 | 论文步骤2：降 fcMin 抑制静止抖动 |

**预期：静止抖动 15.7→5-10px，总滞后 ~220px**

### 🔧 改动文件

| 文件 | 改动 |
|------|------|
| `CursorController.swift:195-196` | fcMin 1.5→0.8 |

---

## v0.4.0 (2026-06-06)

| 属性 | 内容 |
|------|------|
| **分支** | `feat/tune-responsiveness` |
| **Commit** | `ce7aecc` `b53d66f` |
| **Plan** | `.hermes/plans/21-整合-chirality修复+响应调优.md` |
| **基准** | `v0.3.0-baseline` |
| **作者** | Claude Opus 4.8 |

### 🐛 修复

| 问题 | 根因 | 修复方式 |
|------|------|---------|
| 左手方向反了 | `-rawOffsetX` 双重镜像补偿 | 去 chirality X 翻转，原点校准自适应 |
| Chirality 帧间翻转 | Vision 左右手识别不稳定 | 滞后锁：连续 3 帧同向才切换 |
| 首帧光标跳 (0,0) | `currentPosition = .zero` 未初始化 | 校准完成时初始化到屏幕中心 |

### ⚡ 性能优化

| 参数 | 旧值 | 新值 | 效果 |
|------|:--:|:--:|------|
| 1€ Filter `beta` | 0.007 | 0.05 | 快移自动轻滤，延迟 261→180px |
| 1€ Filter `fcMin` | 1.0 | 1.5 | 微动更灵敏 |
| 120Hz lerp | 0.50 | 0.65 | 追赶快30%，T-C滞后 67→60px |

**总滞后 328→240px（🔽27%）**

### 🔧 改动文件

| 文件 | 改动 |
|------|------|
| `CursorController.swift` | 去 chirality 翻转 + currentPosition 初始化 |
| `HandPoseDetector.swift` | chirality 滞后锁 |
| `MotionControlApp.swift` | lerp 0.50→0.65 |
| `Tests/` | 更新左右手同向测试 |

---

## v0.3.1 (2026-06-06)

| 属性 | 内容 |
|------|------|
| **分支** | `feat/tune-responsiveness` |
| **Commit** | `ce7aecc` |
| **Plan** | `.hermes/plans/20-跟手响应调优.md` |
| **基准** | `v0.3.0-baseline` |
| **作者** | Claude Opus 4.8 |

### ⚡ 性能优化

| 参数 | 旧值 | 新值 | 效果 |
|------|:--:|:--:|------|
| 1€ Filter `beta` | 0.007 | 0.05 | 快移自动轻滤，延迟 261→180px |
| 1€ Filter `fcMin` | 1.0 | 1.5 | 微动更灵敏 |
| 120Hz lerp | 0.50 | 0.65 | 追赶快30%，T-C滞后 67→60px |

**总滞后 330→240px（🔽27%）**

### 🔧 改动文件

| 文件 | 改动 |
|------|------|
| `CursorController.swift` | filterX/Y 参数 beta + fcMin |
| `MotionControlApp.swift` | 120Hz lerp 值 |

---

## v0.3.0 (2026-06-06)

| 属性 | 内容 |
|------|------|
| **分支** | `feat/absolute-position-mapping` |
| **Commit** | `0e00a63` `91aa872` `b07b6f1` `45698b6` |
| **Plan** | `.hermes/plans/18-绝对位置映射-左右手-双手手势.md` |
| **作者** | Claude Opus 4.8 |

### 🏗️ 架构变更

**核心：增量式 delta 跟踪 → 绝对位置映射**

```
旧 (v0.1-0.2): 光标 += delta(手n, 手n-1) × velocity × factor
              问题：漂移不可逆、初始跳跃、回不了正

新 (v0.3.0):   光标 = 屏幕中心 + (手位置 - 原点) × 屏幕尺寸 × 增益
              优势：手在原点 = 光标在中心，永不漂移
```

### ✨ 新功能

| 功能 | 实现 | 文件 |
|------|------|------|
| **原点自动校准** | 手入画面 0.5s 内累积 palmCenter EMA 作为静止原点，校准期间光标不移动 | `CursorController.swift` |
| **校准状态机** | idle → calibrating → tracking 三态流转，手丢失 >15 帧重置 | `CursorController.swift` |
| **左右手自动识别** | Vision `chirality` 自动检测，左手 x 方向自动镜像，无需用户配置 | `HandPoseDetector.swift` |
| **palmCenter 三级降级** | wrist+MCP → MCP → 指尖，确保手腕出画面时仍可跟踪 | `HandPoseDetector.swift` |

### 🔧 改动文件

| 文件 | 改动 | 行数 |
|------|------|:--:|
| `CursorController.swift` | 新增校准状态机 + `updateWithAbsolutePosition` | +90 |
| `MotionControlApp.swift` | 替换增量跟踪为校准状态机 + 原点映射 | +30 -60 |
| `HandPoseDetector.swift` | chirality + HandSide 枚举 + palmCenter 降级 | +30 |
| `Docs/01-需求文档.md` | 更新光标控制章节为绝对映射方案 | -- |
| `Docs/02-技术方案.md` | 新增 v3.0 架构变更记录 | -- |
| `CHANGELOG.md` | 本文件更新 | -- |

### 🐛 修复

| 问题 | 根因 | 修复方式 |
|------|------|---------|
| 手入画面时光标大幅跳跃 | 增量式 tracking 第一帧 delta 大 | 校准期 0.5s 光标完全不动 |
| 手回到原位光标不归位 | 增量式漂移不可逆 | 绝对映射：手在原点 = 光标在中心 |
| 手腕出画面时光标停止 | palmCenter 需要 wrist 才计算 | 三级降级到 MCP/指尖 |
| 摄像头镜像方向反了 | 自拍镜像未补偿 | X/Y 取反（`screenCX - offsetX`） |
| pre-commit hook 误拦截 | P-BLOCKED grep 匹配了 P-LOGIC 条目 | 精确提取 P-BLOCKED 段做匹配 |
| production print 刷屏 | CursorController 2 条 `print()` 未包 `#if DEBUG` | 包裹 `#if DEBUG`（Gate 4 发现） |

### 📋 已知问题

- 手势动作映射全部禁用（测试模式，`onGesture` 第一行 return）
- 双手手势接口已预留（`HandSide` 枚举），功能未实现
- 原点校准依赖手入画面后 0.5s 静止，手入画面就移动会导致原点不准

---

## v0.2.0 (2026-06-06)

| 属性 | 内容 |
|------|------|
| **分支** | `feat/palm-center-cursor` |
| **Commit** | `185cd32` `dac6285` `80cdb6d` |
| **Plan** | `.hermes/plans/17-palm-center-cursor-4k-fix.md` |
| **作者** | Claude Opus 4.8 |

### ✨ 新功能

| 功能 | 实现 |
|------|------|
| **手掌几何中心光标控制** | palmCenter（手腕+4MCP 均值）替代 indexTip，SRM 2025 论文方案 |
| **pre-commit hook 门禁** | PERMISSIONS.md 权限分级（P-PARAM / P-LOGIC / P-ARCH / P-BLOCKED） |
| **版本管理系统** | VERSION + CHANGELOG.md + git tag |
| **DEBUG print 防护** | `#if DEBUG` 包裹所有调试输出 |

### 🔧 改动

- `CursorController.swift`: 灵敏度基于参考分辨率 1920×1080 归一化（修复 4K 屏幕 7.8x 问题）
- `MotionControlApp.swift`: 去掉手指伸展检测（`fingerExtension`），改为手部置信度 >0.15 激活
- 手势动作映射全部禁用（`onGesture` return）

### 🐛 修复

- 4K 屏幕灵敏度从等效 7.8x → 3.0x
- 手离开画面时光标不再跳到旧位置（`fingerActive` guard）
- pre-commit hook P-BLOCKED 误匹配 P-LOGIC 条目

---

## v0.1.0 (2026-05-27)

### 首次发布

- 摄像头采集（AVCapture）
- Vision 手部 21 点 + 面部 76 点 + 嘴型检测
- 食指指尖 cursor 控制（增量 delta + Velocity EMA）
- 手势识别：swipeUp/Down、indexTap、pinch 等 17 种
- 注视估计（yaw/pitch → 光标偏移，v0.2.0 已禁用）
- SFSpeechRecognizer 语音识别（zh-CN）+ 嘴型触发
- 配置面板（手势映射 + 参数编辑 + 多方案）
- UIElementScanner 磁吸辅助
