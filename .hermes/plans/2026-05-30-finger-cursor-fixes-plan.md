# 手指光标激活 + Y 轴方向修复 — 实施计划

> **基于日志分析得出的两个 bug**

**目标：** 修复手指方向光标（finger cursor）无法激活的问题，以及 Y 轴方向反转问题

---

## 改动类型分级

| 改动 | 类型 | 说明 |
|------|------|------|
| Y 轴翻转修复 | P-LOGIC | 修改 MotionControlApp.swift 方向计算 |
| 手指激活条件放宽 | P-LOGIC | 修改 MotionControlApp.swift 阈值逻辑 |

---

### Task 1：修复 Y 轴翻转

**Objective：** 将 `dy = pip.y - tip.y` 改为 `dy = tip.y - pip.y`，消除双翻转 bug

**类型：** P-LOGIC

**根因分析：**
- Vision 坐标系 (0,0)=左下，y 向上 → 指上时 `tip.y > pip.y`
- 原代码 `dy = pip.y - tip.y` 做了第一层翻转（让指上时 dy 为负）
- `computeCursor` 在 top-left 坐标系中累加：dy 负 → y 减小 → 光标上移
- `mouseController.moveCursor` 又做 `screenHeight - y` 第二层翻转
- **结果**：指上时经过两层翻转，光标实际往下走

**Files：**
- Modify: `Sources/MotionControl/App/MotionControlApp.swift:142`

**改动（一行）：**
```swift
// 改前：
let dy = pip.y - tip.y   // Vision y向上，翻转
// 改后：
let dy = tip.y - pip.y   // Vision y向上，保持方向一致
```

**原理验证（改后路径）：**
- 指上 → `tip.y > pip.y` → `dy = tip.y - pip.y` > 0
- `direction.y` > 0 → `rawVy` > 0 → `filteredVelocity.y` > 0
- `newBase.y += positive * dt` → y 增大（在 top-left 坐标系中向下走）
- `mouseController.moveCursor` 翻转：`screenHeight - (更大的 y)` = 更小的值 → **光标实际向上走 ✓**

**验证方法：** 编译后手指出上，光标应向上移动

---

### Task 2：修复手指激活条件

**Objective：** 放宽 `otherLow` 阈值，让食指伸出时其他手指的正常伸展不会阻止光标激活

**类型：** P-LOGIC

**根因分析：**
- 当前条件：`middleExt < 0.15 && ringExt < 0.15 && littleExt < 0.15 && thumbExt < 0.15`
- 实测 data：即使食指明显伸出做指点姿势，middleExt 也在 0.14~0.24
- 条件几乎永远为 false → `updateFingerDirection` 从不调用 → `fingerActive = false` → 光标锁在 (0,0)
- **实际不存在的手指光标慢的问题——光标根本就没激活过**

**Files：**
- Modify: `Sources/MotionControl/App/MotionControlApp.swift:159`

**改动方案一：放宽阈值（推荐，改动最小）**
```swift
// 改前：
let otherLow = middleExt < 0.15 && ringExt < 0.15 && littleExt < 0.15 && thumbExt < 0.15
// 改后：
let otherLow = middleExt < 0.30 && ringExt < 0.30 && littleExt < 0.30 && thumbExt < 0.30
```

**改动方案二：用比值（更鲁棒，但改动更大）**
```swift
// 改后：食指伸展度明显大于其他手指
let indexDominant = indexExt > middleExt * 1.3 && indexExt > ringExt * 1.3
```

**推荐方案一**，因为：
1. 改动最小（一行改一个数）
2. 实测数据中食指伸直时其他指伸展在 0.14~0.24，阈值提到 0.30 即可通过
3. 五指全伸时其他指伸展通常 > 0.30，仍被 `allHigh` 条件阻断

**验证方法：** 编译后食指伸出光标应能移动，握拳/五指全伸时光标不动

---

## 审批

状态：✅ 已确认
确认人：老板
确认时间：2026-05-30

---

> 按 Task 顺序用 Aider 执行，每个 Task 独立编译验证 + 提交。
