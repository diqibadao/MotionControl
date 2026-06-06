# 磁吸性能修复 — 实施计划

**两个问题，都在 UIElementScanner 内修，CursorController 不动**

---

## 问题分析

| 问题 | 表现 | 根因 | 修法 |
|------|------|------|------|
| ①主线程卡 | computeCursor 耗时 2~3 秒 | elementAt 在主线程调 AX API | 放后台队列，缓存结果 |
| ②缓存太少 | 仅 3 个元素 | 轻量扫描器没扫描窗口 | 改回扫前窗元素 |

**CursorController 不动** — 磁吸逻辑是对的，只是输入数据（elementAt 结果 + 缓存）慢/少。

---

## 方案

```
后台队列 (每 200ms):
  1. 读 NSEvent.mouseLocation（当前光标位置）
  2. 调 1 次 elementAt（不是 5 次）
  3. 存到 nearElement 缓存
  
后台队列 (每 5 秒):
  1. 扫描前窗（最前面的 App 窗口）
  2. 收集交互元素 → elements 缓存

主线程每帧:
  computeCursor 只读缓存:
    scanner.nearElement（近距磁吸）
    scanner.elements（远距磁吸回退）
    0 AX API 调用，耗时 <0.001ms
```

---

## Task 1：elementAt 放后台，缓存结果

**Files：**
- Modify: `Sources/MotionControl/Control/UIElementScanner.swift`

**改动：**

新增属性和方法：
```swift
// 缓存：光标附近的元素（由后台队列更新）
private(set) var nearElement: UIElementInfo? = nil

// 后台刷新光标附近元素
func refreshNearCursor() {
    backendQueue.async { [weak self] in
        guard let self = self else { return }
        let cursor = NSEvent.mouseLocation
        // 只查 1 个点（光标位置），不查 5 个
        if let el = self.elementAt(position: cursor) {
            let center = CGPoint(x: el.frame.midX, y: el.frame.midY)
            let dx = center.x - cursor.x
            let dy = center.y - cursor.y
            let dist = sqrt(dx*dx + dy*dy)
            if dist < 120 {
                DispatchQueue.main.async {
                    self.nearElement = el
                }
                return
            }
        }
        DispatchQueue.main.async {
            self.nearElement = nil
        }
    }
}
```

在 `start()` 的 timer 中，除了 scan，再加一个高频 timer（每 200ms）调用 `refreshNearCursor()`。

**CursorController.swift 改动：**
```swift
// 磁吸部分：去掉 elementAt 查询循环，改为只读缓存
if let scanner = uiScanner {
    // ① 近距：读缓存（后台更新，不阻塞）
    if let near = scanner.nearElement, nearElement距离<120 {
        // 算吸力
    }
    // ② 远距：读 elements 缓存
    for element in scanner.elements { ... }
}
```

---

## Task 2：缓存扫描改扫前窗

**Files：**
- Modify: `Sources/MotionControl/Control/UIElementScanner.swift`

将 `scan()` 改为只扫最前面 App 的窗口：
```swift
private func scan() {
    // 只扫最前面的 App
    guard let frontApp = NSWorkspace.shared.frontmostApplication,
          frontApp.activationPolicy == .regular else { return }
    
    let pid = frontApp.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)
    
    guard let windowsRef = getAttributeValue(appElement, kAXWindowsAttribute as String) else { return }
    let windowElements = axElements(from: windowsRef)
    
    for window in windowElements {
        // 只扫第一层子元素，不递归
        guard let childrenRef = getAttributeValue(window, kAXChildrenAttribute as String) else { continue }
        let children = axElements(from: childrenRef)
        for child in children {
            guard let info = extractElementInfo(child) else { continue }
            // 只保留已知角色的交互元素
            let interactiveRoles: Set = ["AXButton","AXTextField","AXRadioButton","AXPopUpButton","AXCheckBox","AXSlider","AXDisclosureTriangle","AXLink","AXImage","AXRow","AXCell","AXTab","AXMenuButton"]
            if interactiveRoles.contains(info.role) {
                newElements.append(info)
            }
        }
    }
    
    DispatchQueue.main.async {
        self.elements = newElements
    }
}
```

---

## 改动边界

| 模块 | 动/不动 | 文件 |
|------|:-------:|------|
| UIElementScanner | **改** | elementAt 放后台 + 缓存 |
| CursorController | **极小改** | 磁吸只读缓存，去 elementAt 循环 |
| MotionControlApp | ❌ 不动 | — |
| DetectionPipeline | ❌ 不动 | — |
| MouseController | ❌ 不动 | — |

---

## 审批

状态：✅ 已确认
确认人：老板
确认时间：2026-05-30

---

> Task 1 和 2 合并到一次 Aider 调用（改同一文件），再加一次调 CursorController。
