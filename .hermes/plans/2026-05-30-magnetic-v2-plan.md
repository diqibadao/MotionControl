# 日志补齐 + 位置查询改方案 — 实施计划

---

## 背景

现有磁吸方案的三个问题：

| 问题 | 表现 | 根因 |
|------|------|------|
| 日志缺失 | 磁吸代码无 EventLogger | Aider prompt 没带规范要求 |
| 元素漏检 | SwiftUI `.onTapGesture` 等元素吸不到 | AXPress 检测+角色白名单不可靠 |
| 扫描太慢 | 全屏遍历 2107 元素需 ~3 秒 | 递归遍历整个 AX 树 |

---

## 新方案：位置查询 + 扫描器缓存双保险

```
每帧（30fps）：
  ① 位置查询：AXUIElementCopyElementAtPosition
     → 查光标位置 (x,y)、(x±60, y)、(x, y±60) 共 5 个点
     → 每个点 <0.5ms，总计 <3ms
     → 100% 不漏任何元素（不管什么角色、有没有 AXPress）

  ② 扫描器缓存（保留，每 5 秒一次）
     → 覆盖远距磁吸（120px 内的 UI 元素）
     → 位置查询补了近距漏检

  ③ 合并两者结果 → 取最近元素 → 计算吸力
```

---

## 各层边界

| 层 | 文件 | 动/不动 | 说明 |
|----|------|:-------:|------|
| **输入** | CameraService.swift | ❌ 不动 | 采集 |
| | HandPoseDetector.swift | ❌ 不动 | Vision 检测 |
| | DetectionPipeline.swift | ❌ 不动 | 帧处理 |
| **计算** | **UIElementScanner.swift** | **✏️ 改** | **位置查询 + 简化扫描器** |
| | **CursorController.swift** | **✏️ 改** | **补 EventLogger** |
| **输出** | MouseController.swift | ❌ 不动 | 系统光标 |

---

### Task 1：补齐所有新代码的 EventLogger

**Objective：** 磁吸模块每个方法打 IN/OUT/耗时日志

**类型：** ALL（P-PARAM）

**Files：**
- Modify: `Sources/MotionControl/Control/UIElementScanner.swift`
- Modify: `Sources/MotionControl/Control/CursorController.swift`

**需要补日志的方法：**

**UIElementScanner.swift：**
- `scan()` — 扫描开始/结束+耗时+元素数
- `collectInteractiveAXElements()` — 递归入口
- `isInteractive()` — 检查结果

**CursorController.swift：**
- `updateTargetPosition()` — target 坐标 → 平滑后坐标+耗时
- `computeCursor()` — 返回的最终位置+耗时
- 磁吸循环 — 找到的元素+距离+吸力

**格式：**
```swift
EventLogger.log(event: "method_name", frame: nil,
                input: "IN", output: "OUT", duration: elapsedMs)
```

---

### Task 2：UIElementScanner 改位置查询方案

**Objective：** 废弃 `collectInteractiveAXElements` 递归遍历和 `isInteractive` 双保险，改用 `AXUIElementCopyElementAtPosition` 查询光标附近元素

**类型：** P-ARCH

**Files：**
- Rewrite: `Sources/MotionControl/Control/UIElementScanner.swift`

**具体改动：**

**删除：**
- `collectInteractiveAXElements()` 方法（递归遍历整棵树）
- `isInteractive()` 方法（AXPress + 角色白名单）
- `axElements(from:)` 方法（CFArray 转换）

**保留：**
- `UIElementInfo` 结构体
- `start()` / `stop()` 定时器框架（间隔保持 5000ms）
- `getAttributeValue()` 辅助方法
- 后台 `backendQueue`

**新增：**
```swift
/// 查询光标附近指定位置的元素
/// - Parameters:
///   - position: 屏幕坐标
///   - threshold: 搜索半径
/// - Returns: 找到的 UI 元素，nil 表示无元素
func elementAt(position: CGPoint) -> UIElementInfo? {
    let systemWide = AXUIElementCreateSystemWide()
    var ref: AXUIElement?
    let err = AXUIElementCopyElementAtPosition(
        systemWide, Float(position.x), Float(position.y), &ref
    )
    guard err == .success, let element = ref else { return nil }
    return extractElementInfo(element)
}

/// 从 AXUIElement 提取信息
private func extractElementInfo(_ element: AXUIElement) -> UIElementInfo? {
    // 读 role/title/position/size/enabled
    // 返回 UIElementInfo 或 nil
}

/// 全屏扫描（简化版：只扫窗口级的交互元素，不递归）
/// 保留用于远距磁吸，但大幅缩小范围
func scanVisibleElements() { ... }
```

**扫描器改为：** 不递归遍历全部子元素，只扫窗口的直接子级 + 已知交互角色。预计从 2107 降到 300-500 个元素，扫描时间从 3 秒降到 <500ms。

---

### Task 3：CursorController 磁吸改用位置查询

**Objective：** computeCursor 中磁吸改用位置查询 + 扫描器缓存双保险

**类型：** P-LOGIC

**Files：**
- Modify: `Sources/MotionControl/Control/CursorController.swift`

**磁吸逻辑改为：**
```swift
// ① 位置查询：查光标附近 5 个点
let checkPoints: [CGPoint] = [
    cursor,
    CGPoint(x: cursor.x + 60, y: cursor.y),
    CGPoint(x: cursor.x - 60, y: cursor.y),
    CGPoint(x: cursor.x, y: cursor.y + 60),
    CGPoint(x: cursor.x, y: cursor.y - 60),
]
for pt in checkPoints {
    if let el = scanner?.elementAt(position: pt) {
        // 记录为候选
    }
}

// ② 扫描器缓存（远距）
let nearestCached = findNearest(from: scanner?.elements ?? [], to: cursor, threshold: 120)

// ③ 合并，取最近
// ④ 算吸力（同现有逻辑）
```

---

## 审批

待你确认后再填写。
