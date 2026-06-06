# MotionControl 更新日志

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
