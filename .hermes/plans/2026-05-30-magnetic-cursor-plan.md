# 磁性光标 — 实施计划

**基于 AX API 扫描 UI 元素 + 光标磁吸辅助定位**

---

## 架构总览

完整数据流：

```
30fps 线程                             后台线程 (每 500ms)
┌─────────────┐                       ┌──────────────────┐
│ 摄像头 → 手指  │                       │ AX API 扫全屏 UI  │
│ → tip坐标映射  │                       │ → 缓存交互元素    │
│ → EMA 平滑    │                       │  (位置/大小/类型) │
│ → cursor位置  │                       │                  │
└──────┬───────┘                       └────────┬─────────┘
       │ 每帧                                   │ 更新缓存
       ▼                                        ▼
┌──────────────────────────────────────────────┐
│  MagneticAttractor                            │
│  cursor附近有已缓存的UI元素吗？               │
│  有 → 元素距离 < 80px → 加柔和吸引力          │
│  有 → 元素距离 < 30px → 减速（方便停稳）      │
│  无 → 不干涉                                  │
│  全部耗时 < 0.5ms                             │
└──────────────────────┬───────────────────────┘
                       ▼
┌──────────────────────────────────────────────┐
│  CursorController.computeCursor() → 最终位置  │
│  MouseController.moveCursor()                │
└──────────────────────────────────────────────┘
```

---

## 各层边界（红线）

| 层 | 文件 | 动/不动 | 说明 |
|----|------|:-------:|------|
| **输入** | CameraService.swift | ❌ 不动 | 采集 |
| | HandPoseDetector.swift | ❌ 不动 | Vision 检测 |
| | DetectionPipeline.swift | ❌ 不动 | 帧处理 |
| | HandPoseResult.swift | ❌ 不动 | 数据类型 |
| | GestureAnalyzer.swift | ❌ 不动 | 手势分类 |
| **计算** | **UIElementScanner.swift** | **🆕 新建** | **扫 UI 元素 + 缓存** |
| | **CursorController.swift** | **✏️ 扩展** | **加磁吸逻辑** |
| **输出** | MouseController.swift | ❌ 不动 | 系统光标操作 |
| | MotionControlApp.swift | ✏️ 极小改动 | 初始化 scanner |

---

### Task 1：新建 UIElementScanner

**Objective：** 后台线程周期扫描 UI 元素树，缓存交互元素的位置/大小/类型

**类型：** 新增模块（P-ARCH）

**Files：**
- Create: `Sources/MotionControl/Control/UIElementScanner.swift`

**代码设计：**

```swift
import AppKit
import ApplicationServices

/// 屏幕上可交互的 UI 元素
struct UIElementInfo {
    let role: String        // "AXButton" / "AXTextField" / "AXCheckBox"
    let title: String       // "关闭" / "提交" / "搜索"
    let frame: CGRect       // 屏幕坐标 (x, y, w, h)
    let isEnabled: Bool
    let subrole: String?    // "AXCloseButton" 等
}

/// 后台扫描 UI 元素树，缓存到内存
class UIElementScanner {
    // 缓存：当前屏幕上所有交互元素
    private(set) var elements: [UIElementInfo] = []
    
    // 扫描队列（非主线程）
    private let scanQueue = DispatchQueue(
        label: "com.motioncontrol.uiscan",
        qos: .utility
    )
    
    // 扫描定时器（每 500ms）
    private var timer: DispatchSourceTimer?
    
    func start() {
        let t = DispatchSource.makeTimerSource(queue: scanQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.scan() }
        t.resume()
        timer = t
    }
    
    func stop() {
        timer?.cancel()
        timer = nil
        elements = []
    }
    
    private func scan() {
        // 1. 获取所有运行中的 App
        // 2. 对每个 App 获取窗口
        // 3. 对每个窗口获取子元素（按钮/输入框/复选框...）
        // 4. 只保留交互元素（kAXButton, kAXTextField 等）
        // 5. 保存位置+大小+类型+名字
        // 6. 替换缓存
    }
}
```

**性能设计：**
- 不在主线程跑 ✅
- 每 500ms 一次，不是每帧 ✅
- `qos: .utility` 优先级低，不影响手势检测 ✅
- 缓存替换是原子操作（一个属性赋值），无锁竞争 ✅
- 扫描慢时（>500ms）自动跳过下一轮 ✅（GCD timer 有 leeway）

**AX API 调用细节：**

```swift
// 遍历所有进程（优化：获取有窗口的 App 列表更快）
let apps = NSWorkspace.shared.runningApplications
    .filter { $0.activationPolicy == .regular }

for app in apps {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    
    // 获取窗口
    var windows: CFArray?
    AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows)
    
    guard let windowArray = windows as? [AXUIElement] else { continue }
    
    for window in windowArray {
        // 获取子元素
        var children: CFArray?
        AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)
        
        guard let childArray = children as? [AXUIElement] else { continue }
        
        for child in childArray {
            // 读取属性（位置、大小、角色、标题、是否可用）
            var position: CFTypeRef?
            var size: CFTypeRef?
            var role: CFTypeRef?
            var title: CFTypeRef?
            var enabled: CFTypeRef?
            
            AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &position)
            AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &size)
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &title)
            AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabled)
            
            // 只缓存交互元素
            guard let roleStr = role as? String,
                  UIElementScanner.isInteractive(role: roleStr) else { continue }
            
            var point = CGPoint.zero
            var sizeVal = CGSize.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &point)
            AXValueGetValue(size as! AXValue, .cgSize, &sizeVal)
            
            let el = UIElementInfo(
                role: roleStr,
                title: title as? String ?? "",
                frame: CGRect(origin: point, size: sizeVal),
                isEnabled: enabled as? Bool ?? true
            )
            results.append(el)
        }
    }
}

// 交互元素类型白名单
static func isInteractive(role: String) -> Bool {
    switch role {
    case kAXButtonRole, kAXTextFieldRole, kAXCheckBoxRole,
         kAXRadioButtonRole, kAXComboBoxRole, kAXSliderRole,
         kAXPopUpButtonRole, kAXMenuButtonRole, kAXDisclosureTriangleRole:
        return true
    default:
        return false
    }
}
```

---

### Task 2：CursorController 加磁吸逻辑

**Objective：** 每帧在 computeCursor 中检查光标附近是否有已缓存的 UI 元素，若有则添加柔和吸引力

**类型：** P-LOGIC

**Files：**
- Modify: `Sources/MotionControl/Control/CursorController.swift`

**改动（在 computeCursor 中增加磁吸步骤）：**

```swift
func computeCursor(screenSize: CGSize, sensitivity: Float, dt: Double = 1.0 / 30.0) -> CGPoint {
    var cursor = currentPosition
    
    // 磁吸：查缓存中的 UI 元素
    if let nearest = findNearestElement(to: cursor, threshold: 80) {
        let distance = distance(from: cursor, to: nearest.frame)
        
        if distance < 30 {
            // 非常接近 → 减速（磁吸锁定）
            // 不拉，让用户自己点，但光标移动变慢
            // 通过临时降低 EMA factor 实现
        } else if distance < 80 {
            // 较近 → 柔和吸引力
            let pull = (80 - distance) / 80  // 0~1
            let center = CGPoint(
                x: nearest.frame.midX,
                y: nearest.frame.midY
            )
            cursor.x += (center.x - cursor.x) * pull * 0.15
            cursor.y += (center.y - cursor.y) * pull * 0.15
        }
    }
    
    // 加入注视偏移（不变）
    if gazeActive { ... }
    
    // 限制在屏幕内（不变）
    cursor.x = max(0, min(cursor.x, screenSize.width))
    cursor.y = max(0, min(cursor.y, screenSize.height))
    
    return cursor
}

// 新方法：找光标最近的交互元素
private func findNearestElement(to point: CGPoint, threshold: CGFloat) -> UIElementInfo? {
    let elements = uiScanner.elements  // 读缓存（原子读，无锁）
    var nearest: UIElementInfo?
    var minDist = threshold
    
    for el in elements where el.isEnabled {
        let center = CGPoint(x: el.frame.midX, y: el.frame.midY)
        let dx = center.x - point.x
        let dy = center.y - point.y
        let dist = sqrt(dx*dx + dy*dy)
        if dist < minDist {
            minDist = dist
            nearest = el
        }
    }
    return nearest
}
```

**性能设计：**
- 遍历缓存中的元素 = 几十到几百个，O(n) 扫描
- 每个元素算一次距离（乘加+sqrt）
- 典型耗时任 < 0.5ms
- 如果元素太多（>500），只检查光标附近 200px 内的窗口的元素（空间索引）

---

### Task 3：MotionControlApp 初始化 scanner

**Objective：** 在 App 启动时初始化 UIElementScanner，传给 CursorController

**类型：** 极小改动（P-LOGIC）

**Files：**
- Modify: `Sources/MotionControl/App/MotionControlApp.swift`

在 ContentView 初始化中添加：
```swift
private let uiScanner = UIElementScanner()

// 在 .onAppear 中：
uiScanner.start()

// 在 .onDisappear 中：
uiScanner.stop()
```

CursorController 引用 scanner：
```swift
// CursorController 初始化时传入或通过属性设置
cursorController.uiScanner = uiScanner
```

---

## 性能保障

| 操作 | 线程 | 频率 | 耗时 | 风险 |
|------|------|:----:|:----:|:----:|
| AX API 全屏扫描 | 后台 queue | 500ms | ~120ms | ❌ 不能上主线程 |
| 缓存读取 | 主线程 | 每帧 | <0.001ms | ✅ 纯内存 |
| 最近元素遍历 | 主线程 | 每帧 | ~0.5ms | ✅ 可接受 |
| 磁吸计算 | 主线程 | 每帧 | ~0.01ms | ✅ 三行数学 |

**最差情况：** 屏幕上 500+ 交互元素 → 遍历耗时 ~2ms → 仍然在 33ms 帧预算内 ✅

---

## 审批

状态：✅ 已确认
确认人：老板
确认时间：2026-05-30

---

> 三个 Task：
> 1. 新建 UIElementScanner.swift（新文件，Aider 创建）
> 2. 扩展 CursorController.swift（加磁吸逻辑）
> 3. MotionControlApp.swift（初始化 scanner）
>
> 顺序执行，每个编译验证。
