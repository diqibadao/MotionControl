# Gate 2 Plan — palmCenter 三指 + edgeDamping 移除

**日期**：2026-06-10
**分支**：feat/frame-loss-guard
**触发**：PECF 报告中三个问题的修复

---

## 问题回顾

| # | 问题 | 根因 | 修复 |
|---|------|------|------|
| 1 | 底部触达受限 | palmCenter 含 wrist 抖动 + 权重不合理 | 改用中三指 MCP 均值 |
| 3 | 边缘粘连 | edgeDamping 0.6 破坏绝对映射线性 | 去掉 edgeDamping |

---

## 改动清单（2 文件）

### 1. `HandPoseDetector.swift` — palmCenter

**现状**：
```swift
// MCP 80% + wrist 20%（wrist缺失时纯MCP）
mcps = [indexMCP, middleMCP, ringMCP, littleMCP]
mcpX * 0.8 + wristX * 0.2
```

**改为**：
```swift
// 中三指 MCP 均值（index + middle + ring），去掉 wrist 和 littleMCP
mcps = [indexMCP, middleMCP, ringMCP]
// 纯 MCP 均值，不需要加权
```

**原因**：
- wrist 在画面边缘时抖动大（44.5px），拖累 palmCenter 稳定性
- littleMCP 检测率最低（90.3%），经常缺失 → 拉偏中心
- 中三指（index/middle/ring）检测率最高（93-96%），位置最稳定
- 去掉 wrist 权重后 palmCenter 下移 → 改善底部触达

### 2. `CursorController.swift` — edgeDamping

**现状**：
```swift
let atScreenEdge = cursorX <= 5 || cursorX >= screenSize.width - 5
                || cursorY <= 5 || cursorY >= screenSize.height - 5
let edgeDamping: CGFloat = atScreenEdge ? 0.6 : 1.0
let dampedX = screenCX - offsetX * screenSize.width * effectiveGain * edgeDamping
let dampedY = screenCY + offsetY * screenSize.height * effectiveGain * edgeDamping
```

**改为**：删除 edgeDamping 相关 7 行，`updateWithAbsolutePosition()` 直接用 `cursorX/cursorY` 进 clamp：

```swift
let cursorX = screenCX - offsetX * screenSize.width * effectiveGain
let cursorY = screenCY + offsetY * screenSize.height * effectiveGain

let rawTarget = CGPoint(
    x: max(0, min(cursorX, screenSize.width)),
    y: max(0, min(cursorY, screenSize.height))
)
```

**原因**：
- 业界标准：绝对映射 + clamp，不加边缘非线性阻尼
- edgeDamping 破坏手→光标线性关系，造成粘连、跳变、反转
- clamp 已天然防止越界

---

## 不碰

- 手势识别逻辑
- 校准流程
- 帧丢失保护
- 三区可变增益

## 验证

1. `swift build` 通过
2. `swift run` → 用户测试 30s
3. 跑 `analyze-cursor-log-v5.py` → 对比 baseline
4. 预期改善：边缘死区 ↓、跳变 ↓、反转 ↓、底部触达改善
5. PECF 五道判定

✅ 已确认

## 风险

- 去掉 wrist 可能导致左手 palmCenter 变高（左手小指检测率也低，但被去掉了）
- 纯 clamp 可能导致光标"撞墙"感 → 可后续加手空间 margin 映射
