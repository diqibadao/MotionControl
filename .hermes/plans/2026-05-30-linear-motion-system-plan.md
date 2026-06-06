# 线性运动系统 — 实施计划

**合并并替换之前所有零散改动**

---

## 核心设计：一条连续的输入→输出曲线

不再用 `* 6` 定值。速度越快倍率越高，一条平滑曲线：

```
手指方向速度 (raw)         倍率         光标速度
      慢  (~50pts/s)       2~3x        ~150pts/s  (精细)
      中  (~150pts/s)      3~6x        ~750pts/s  (正常)
      快  (~300pts/s)      6~10x      ~3000pts/s  (跨屏)
```

**四个改动构成完整系统，缺一不可：**

| # | 改动 | 文件 | 类型 | 来源 |
|---|------|------|------|------|
| 1 | 速度相关加速度曲线 | MotionControlApp.swift | P-LOGIC | libinput Windows ballistics |
| 2 | velocity 自然衰减 | CursorController.swift | P-LOGIC | 全行业标准 |
| 3 | baseCursor 用裁剪值 | CursorController.swift | P-LOGIC | AOSP FingerWorks |
| 4 | 子像素保留（已有） | CursorController.swift | — | 自动满足 |

---

### Task 1：速度相关加速度曲线

**Objective：** 将固定 `* 6` 改为速度相关倍率。速度越慢倍率越低，越快倍率越高

**类型：** P-LOGIC

**Files：**
- Modify: `Sources/MotionControl/App/MotionControlApp.swift:164`

**改动：**

```swift
// 改前：
length: length * screen.width * 6,

// 改后：
// 速度相关加速度倍率：原始速度越大倍率越高
// flength = length * screen.width (原始速度, pts/s)
// multiplier = 2.0 + flength / 300.0 (2x 起步，每 300pts/s 加 1x)
// 约：
//   flength=100 → 2.3x
//   flength=200 → 2.7x
//   flength=300 → 3.0x
//   flength=500 → 3.7x
//   flength=800 → 4.7x
let flength = length * screen.width
let speedMultiplier: CGFloat = 2.0 + flength / 300.0
length: flength * speedMultiplier,
```

**原理：** 线性增加，没有台阶。低速 2x 起步（精细控制不飞），中速自然过渡，高速自动放大。

> 常数 `300.0` 可后续调优。低一点 → 加速度曲线更陡（更快到高速），高一点 → 更平缓（精细区更宽）。

---

### Task 2：velocity 自然衰减

**Objective：** 每帧让 `filteredVelocity` 按比例衰减，手指不动时平滑归零

**类型：** P-LOGIC

**Files：**
- Modify: `Sources/MotionControl/Control/CursorController.swift`

**改动一：computeCursor 前应用衰减**

在第 138-140 行之间（`computeCursor` 方法顶部）插入：

```swift
func computeCursor(screenSize: CGSize, sensitivity: Float, dt: Double = 1.0 / 30.0) -> CGPoint {
    // 0. velocity 自然衰减（手指不动时平滑归零）
    if fingerActive {
        let damping: CGFloat = 0.92
        filteredVelocity.x *= damping
        filteredVelocity.y *= damping
    }
    // 1. 基础位置（不含注视偏移）
    var newBase = baseCursor
```

**衰减曲线：** 每帧乘 0.92，约 9 帧（0.6s@15fps）降到 50%，后续继续衰减到接近零。

**改动二：computeCursor 用裁剪值存 baseCursor（与 Task 3 合并）**

---

### Task 3：baseCursor 用裁剪值，消除跳变

**Objective：** 光标到边后 base 也在边，手反向立刻跟着走

**类型：** P-LOGIC

**Files：**
- Modify: `Sources/MotionControl/Control/CursorController.swift`

**改动：**

```swift
// 改前（第 159-160 行）：
// 4. 存储基座（不含注视偏移）
baseCursor = newBase

// 改后：
// 4. 存储基座（不含注视偏移，用裁剪后的 cursor 避免累积缓冲）
baseCursor = cursor
```

**原理：** `cursor` 是已经 clamp 过的值。用 `cursor` 存 base 意味着每次到边后 base 也在边，手一反向立即反向走。用 `newBase`（未裁剪）会导致 base 在屏幕外累积了数百像素的"虚拟距离"，必须等累积回正才能动——就是那个"跳"。

---

## 改动后完整数据流

```
摄像头帧 → tip-PIP 方向 dx/dy (Vision 0~1)
         → 速度相关加速度曲线（低速2x~高速5x+）
         → OneEuroFilter 平滑
         → filteredVelocity
         ├─ 每帧 × 0.92 衰减
         └─ 每帧 × dt → baseCursor 累加
         → clamp → 裁剪后 cursor
         → baseCursor = cursor（裁剪版）
         → MouseController.moveCursor()
```

**特点：**
- 手指不动 → velocity 自然衰减 → 光标停在原地 ✅
- 手指移动 → 速度越快倍率越高 → 快速跨屏 ✅
- 光标到边 → baseCursor 也在边 → 手一反立即跟着走 ✅
- 低速时倍率低 → 精细控制不飞 ✅

---

## 审批

状态：✅ 已确认
确认人：老板
确认时间：2026-05-30

---

> Task 1-3 顺序执行，每个独立编译验证+提交。其中 Task 2 和 3 改同一个文件(CursorController.swift)，可合并一次 Aider 调用。
