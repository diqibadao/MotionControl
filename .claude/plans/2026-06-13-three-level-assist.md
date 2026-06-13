# Gate 2 Plan — 三级辅助瞄准（L1 惯性 + L2 偏置 + L3 磁吸）

**日期**：2026-06-13
**分支**：feat/frame-loss-guard
**触发**：手追踪光标（~2000px/s）在 100ms tick 内穿过按钮（30-40px），沙坑减速模型力不从心

---

## 问题

手追踪光标的筛选器经验：**光标速度 >> 按钮尺寸 / tick 间隔**。

```
v ≈ 2000px/s    tick = 100ms    一步 = 200px
按钮宽 = 30-40px  →  光标一步跨过 5-6 个按钮
```

旧"沙坑"方案（接近按钮→减速到 25%）的实际效果：

```
减速到 500px/s × 0.1s = 50px  >  按钮 40px
→ 仍然一步跨过 → hit/lost 交替抖动
```

**根因**：减速改的是"离开按钮后的速度"，不是"光标在按钮上的位置"。光标从来没真正**被留在**按钮上过。

---

## 方案：三级辅助系统

```
L1  惯性保留         去抖、防高速过冲         始终生效
L2  接近偏置         路过按钮时偏置 target     速度 < 800px/s + 在 60px 内
L3  力场磁吸         软着陆拉向目标中心         光标 < 50px 从目标中心
```

### L1: 惯性保留（已有，不动）

CursorController 的 1€ 滤波 + `updateWithAbsolutePosition` 低通。已可工作。

### L2: 接近偏置（核心新增）

灵感：[Mäkelä 2014 "Magnetic Cursor"](https://dl.acm.org/doi/10.1145/2611009.2611025)

**逻辑**：

```
每 tick（~120Hz）评估：
  if cursorSpeed < speedGate AND nearElement.dist < R_influence:
      bias = nearElement.center - cursorPos
      biasStrength = k × (1 - normalizedDist^p)
      targetPosition += bias × biasStrength
  else:
      正常裸奔
```

**关键设计**：

| 方面 | 做法 | 为什么 |
|------|------|--------|
| 速度门控 | > 800px/s 旁路 | 高速是扫视/寻路，不是瞄准，不应被干扰 |
| 连续度 | 偏置量 = 距离 × 渐变系数 | 用户感觉"被轻轻拉了一下"，不是"被拽过去" |
| 永不 warp | 不 teleport 光标 | 保持手→光标映射的因果关系，用户不失去控制感 |
| nearElement 快路径 | 勾住时跳过全量 AX scan | 避免 L2 导致的性能开销被螺旋放大 |

### L3: 力场磁吸（已有半套，补完）

当前 `ForceFieldState` 已实现力场偏置 `targetPosition`，但缺：

| 缺口 | 补上 |
|------|------|
| 速度门控 | 高速时旁路（和 L2 共用） |
| 滞回退出 | enterRadius = 60px，exitRadius = 78px（130%），防边界抖动 |
| 锁住时不打断 L2 | 同一入口：scanner.nearElement |

---

## 参数表

| 参数 | 起始值 | 调优方向 | 出自 |
|------|--------|---------|------|
| `R_influence` | **60px** | 按钮 30-40px，左右各 20px 缓冲区 | Mäkelä MC1 100px 缩到 60px（按钮更小） |
| `speedGate` | **800px/s** | 约 40% of 2000px/s，实测微调 | 估算 |
| `biasStrength k` | **0.35** | 边缘 35% 偏置，感觉"轻轻一拉" | 参照 Mäkelä sticky factor |
| `forceDecayPower p` | **2.0** | 越大越边缘硬、中心软。2.0 是典型平方衰减 | 力学模型 |
| `hysteresisRatio` | **1.3** | enter=60px, exit=78px，过门多走 30% | 借鉴 aim assist 常规 20-33% |
| `magnetStrength` | **0.6** | 力场拉力倍数，吸住但挣脱不费力 | 你已有 ForceFieldState 调优 |

---

## 改动清单（3 文件）

### 1. `GestureConfig.swift` — 新增参数

```swift
// 三级辅助瞄准参数（Gate 2 Plan 2026-06-13）
var assistSpeedGate: CGFloat = 800     // px/s，超过此速度不介入
var assistRInfluence: CGFloat = 60     // px，接近偏置影响半径
var assistBiasStrength: CGFloat = 0.35  // 0-1，偏置强度系数
var assistDecayPower: CGFloat = 2.0    // 力场衰减幂次
var assistHysteresisRatio: CGFloat = 1.3  // 滞回退出/进入比
```

### 2. `CursorController.swift` — L2 偏置 + 速度门控 + 滞回

在 `updateWithAbsolutePosition()` 中 forceField 段前新增：

```swift
// L2: 接近偏置
let handSpeed = calcHandSpeed(handCenter)  // 已有或用新建计算
if handSpeed < config.assistSpeedGate {
    if let near = scanner.nearElement, near.distance < config.assistRInfluence {
        // 速度门控通过 + 在影响半径内 → 施加偏置
        let t = near.distance / config.assistRInfluence
        let strength = config.assistBiasStrength * (1 - pow(t, config.assistDecayPower))
        targetPosition.x += (near.center.x - targetPosition.x) * strength
        targetPosition.y += (near.center.y - targetPosition.y) * strength
    }
}

// L3: 滞回退出
let exitRadius = config.assistRInfluence * config.assistHysteresisRatio
// 在 ForceFieldState 切换时用 exitRadius 代替 enterRadius 判断退出
```

### 3. `UIElementScanner.swift` — nearElement 快路径保持

**现状**：nearElement 已有但未被有效消费。改为：

```swift
// scan() 开头：如果 nearElement 在 R_influence 内且光标速度低 → 跳过全量扫描
if let near = nearElement, near.distance < config.assistRInfluence, handIsSlow {
    updateNearElement(near)  // 只刷新距离/位置，不重扫 UI
    return
}
```

---

## 不碰

- 1€ 滤波参数（fcMin, fcDynClamp）
- gain（2.0）及三区可变增益
- 原点（0.5, 0.4）
- palmCenter 计算逻辑（中三指 MCP）
- AXHelper 独立进程通信
- 现有回放/分析管道的 baseline 指标
- 日志格式（EventLogger）

---

## 验证方法

| # | 验证项 | 手段 |
|---|--------|------|
| 1 | `swift build` 通过 | 编译 |
| 2 | `swift test` 通过 | 单元测试 |
| 3 | 光标准确性不退化 | 回放 v0.7.4 baseline 日志，对比 J(P) 指标 |
| 4 | 接近偏置可感知 | 开启 30fps 手追踪预览，光标缓慢靠近按钮，观察偏置 |
| 5 | 高速时不介入 | 快速挥手扫描屏幕 → 光标无偏置、无卡顿 |
| 6 | 无新 crash | 连续使用 3 分钟，EventLogger 无 SIGABRT/SIGSEGV |

---

## 风险

| 风险 | 概率 | 缓解 |
|------|------|------|
| nearElement 快路径缓存了过期元素 | 中 | 每 3 个 tick（~25ms）强制刷新一次 |
| handSpeed 计算抖动导致 L2 频繁开关 | 低 | handSpeed 再做一帧低通平滑 |
| 偏置幅度踩到 gain 放大震荡 | 低 | biasStrength ≤ 0.35，衰减幂 ≥ 2.0 |
| 回放 baseline 偏离 | 低 | 偏置只影响交互，不影响回放精度指标（tc_lag/JUMPS） |

---

## 优先级

```
第一轮：L2 接近偏置 + 速度门控（最核心改动，一行 if 解决"高速被干扰"）
第二轮：滞回半径（解决边缘抖动）
第三轮：参数调优（用回放+实测调 R_influence/biasStrength）
```
