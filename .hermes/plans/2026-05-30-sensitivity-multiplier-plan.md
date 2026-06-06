# 灵敏度倍率 + 默认值调整 — 实施计划

**缩小手指操控与物理鼠标的操控范围差距**

---

## 改动

当前 EMA 改完后的映射：
```swift
let targetX = (1.0 - tip.x) * screen.width
let targetY = tip.y * screen.height
```
这是 1:1 映射——手移动一半画面，光标移动一半屏幕。

改为乘灵敏度：
```swift
let config = ConfigManager.shared.currentConfig
let targetX = (1.0 - tip.x) * screen.width * CGFloat(config.mouseSensitivity)
let targetY = tip.y * screen.height * CGFloat(config.mouseSensitivity)
```

**效果：**
| 灵敏度 | 手移多少画面 → 光标走满屏 | 感觉 |
|--------|--------------------------|------|
| 1.0 (原) | 移 100% | 手要摆到边 |
| 2.0 (当前默认) | 移 50% | 跟手但柔和 |
| 4.0 (新默认) | 移 25% | 鼠标准，轻微移动就满屏 |

默认 `mouseSensitivity` 从 2.0 提到 4.0。

> 用户可在配置面板的「鼠标速度」滑块实时调节。

---

## 改动类型分级

| 改动 | 文件 | 类型 | 说明 |
|------|------|------|------|
| 映射乘灵敏度 | MotionControlApp.swift | P-LOGIC | 恢复 config 读取 + 乘 sensitivity |
| 默认灵敏度 2.0→4.0 | GestureConfig.swift | P-PARAM | 改一个数 |

---

### Task 1：映射乘灵敏度

**Files：**
- Modify: `Sources/MotionControl/App/MotionControlApp.swift`

在 `onHandResult` 中，`let screen = ...` 后面恢复读取 config：
```swift
let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
let config = ConfigManager.shared.currentConfig
```
然后在 target 计算中乘以 sensitivity：
```swift
let targetX = (1.0 - tip.x) * screen.width * CGFloat(config.mouseSensitivity)
let targetY = tip.y * screen.height * CGFloat(config.mouseSensitivity)
```

### Task 2：默认灵敏度 2.0→4.0

**Files：**
- Modify: `Sources/MotionControl/Config/GestureConfig.swift`

```swift
// 改前：
var mouseSensitivity: Float = 2.0
// 改后：
var mouseSensitivity: Float = 4.0
```

---

## 审批

状态：✅ 已确认
确认人：老板
确认时间：2026-05-30

---

> 两个 Task，分两次 Aider 调用。先改 MotionControlApp.swift，再改 GestureConfig.swift。
