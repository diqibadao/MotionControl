# 迟滞磁吸 + 灵敏度提升 — 实施计划

---

## 要解决的两个问题

| 问题 | 表现 | 现在的方案 | 要改成 |
|------|------|:----------:|:-------:|
| ①**灵敏度不够** | 手移出摄像头还没指到目标 | `mouseSensitivity=4.0` | 提到 **8.0** |
| ②**磁吸模糊** | 吸力黏黏的不干脆 | 线性拉力 120px→0 | **迟滞状态机** |

---

## 方案①：灵敏度提升

改 `GestureConfig.swift` 默认值：
```swift
var mouseSensitivity: Float = 4.0  // 当前
var mouseSensitivity: Float = 8.0  // 改后
```

**效果：** 手在画面中移动 12.5% → 光标横跨整个屏幕。手不用摆出摄像头范围。

用户可在配置面板的「鼠标速度」滑块实时微调。

---

## 方案②：迟滞磁吸状态机

**替换** CursorController 中现有的线性拉力代码，改为三态状态机：

```
        ┌──────────────────────┐
        │       IDLE           │
        │  光标自由跟踪        │
        │  nearElement < 35px? │──── 是 ──→ SNAP
        └──────────────────────┘
                ↑
                │ 距离 > 50px
                │
        ┌──────────────────────┐
        │       SNAP           │
        │  光标被锁定到元素    │
        │  手指有"阻力"感      │
        │  距离 > 50px?        │──── 是 ──→ IDLE
        └──────────────────────┘
```

### 新增枚举

```swift
enum MagnetState {
    case idle       // 自由，无磁吸
    case snap(UIElementInfo)  // 锁定到某个元素
}
```

### computeCursor 磁吸部分新逻辑

```swift
// 在 computeCursor 中（替换现有线性拉力代码）
switch magnetState {
case .idle:
    // 从 nearElement 找最近的元素
    if let near = scanner.nearElement {
        let center = CGPoint(x: near.frame.midX, y: near.frame.midY)
        let dist = distance(from: cursor, to: center)
        if dist < 35 {  // 接入阈值
            magnetState = .snap(near)
            cursor = center  // 果断锁定到中心
        }
    }
    // 同时还从 scanner.elements 找远距候选（120px 内）
    // 仅用于决定下一步锁定谁，不产生拉力

case .snap(let element):
    let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
    let dist = distance(from: cursor, to: center)
    
    if dist > 50 {  // 释放阈值
        magnetState = .idle
        // 自由了，让光标自然跟随手指
    } else {
        // 锁定状态：光标被拉向元素中心
        // 但不是"定死"，而是"强拉力"——80% 拉向中心 + 20% 跟随手指
        cursor.x += (center.x - cursor.x) * 0.8
        cursor.y += (center.y - cursor.y) * 0.8
    }
}
```

### 效果预期

| 场景 | 手感 |
|------|------|
| 光标在空白区域 | 完全自由，无磁吸 |
| 光标靠近按钮 35px 内 | **咔哒一下锁定**到按钮中心 |
| 锁定后手指继续移动 | 光标被强拉向按钮（80% 阻力） |
| 手指明显偏离 > 50px | 释放，回到自由跟踪 |

---

## 各层边界

| 层 | 文件 | 动/不动 |
|----|------|:-------:|
| 配置默认值 | `GestureConfig.swift` | **改** mouseSensitivity 4.0→8.0 |
| 磁吸状态机 | `CursorController.swift` | **改** 替换线性拉力 |
| 元素扫描 | `UIElementScanner.swift` | ❌ 不（已正常工作） |
| 手指跟踪 | `MotionControlApp.swift` | ❌ 不 |
| 鼠标输出 | `MouseController.swift` | ❌ 不 |

---

## 改动范围

| Task | 改什么 | 类型 |
|------|--------|:----:|
| 1 | `GestureConfig.swift` 默认灵敏度 4.0→8.0 | P-PARAM |
| 2 | `CursorController.swift` 磁吸改为迟滞状态机 | P-LOGIC |

---

## 审批

待你确认后填写。
