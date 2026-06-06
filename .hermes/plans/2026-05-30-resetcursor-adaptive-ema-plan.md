# resetCursor 修复 + 自适应 EMA — 实施计划

**两个问题一个 root cause，都在 CursorController.swift**

---

## 日志分析确认的两个 bug

| 问题 | 表现 | 根因 |
|------|------|------|
| 1. 光标跳回 (0,0) | 移动中突然跳到左上角 | `resetCursor()` 把 `currentPosition` 清零了 |
| 2. 大动作响应慢 | 横移手指要半秒光标才到位 | EMA factor 固定 7，不管多远都用同速度 |

## 修复方案

### Task 1：resetCursor 不重置位置

**Files：**
- Modify: `Sources/MotionControl/Control/CursorController.swift`

**改前：**
```swift
func resetCursor() {
    currentPosition = .zero  // ← 问题：手一丢就跳回 (0,0)
    fingerActive = false
}
```

**改后：**
```swift
func resetCursor() {
    fingerActive = false
    // currentPosition 保持不动。手再回来时从上次位置继续
}
```

### Task 2：自适应 EMA 平滑系数

**Files：**
- Modify: `Sources/MotionControl/Control/CursorController.swift`

**改前：**
```swift
func updateTargetPosition(_ target: CGPoint) {
    let diff = CGPoint(x: target.x - currentPosition.x,
                       y: target.y - currentPosition.y)
    currentPosition.x += diff.x / smoothingFactor  // 固定 7
    currentPosition.y += diff.y / smoothingFactor
    fingerActive = true
}
```

**改后：**
```swift
func updateTargetPosition(_ target: CGPoint) {
    let dx = target.x - currentPosition.x
    let dy = target.y - currentPosition.y
    let distance = sqrt(dx*dx + dy*dy)
    // 自适应：手指跨屏大动作追快点，微调时平滑点
    let factor: CGFloat = distance > 100 ? 4 : 8
    currentPosition.x += dx / factor
    currentPosition.y += dy / factor
    fingerActive = true
}
```

**效果：** 大动作相距 >100px → factor=4（~300ms 到位），小调节 <100px → factor=8（平滑不抖）

---

## 改动范围

| Task | 文件 | 改几行 | 类型 |
|------|------|--------|------|
| 1 | CursorController.swift | 1 行删 | P-LOGIC |
| 2 | CursorController.swift | ~6 行换 | P-LOGIC |

两个 Task 改同一个文件，**一次 Aider 调用搞定**。

---

## 审批

状态：✅ 已确认
确认人：老板
确认时间：2026-05-30

---

> 编译验证后直接重启 App 测试。
