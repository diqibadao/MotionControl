# 光标修复方案 — CGEvent 坐标系问题

## 根因分析

### 已验证的事实（来自日志）

1. `CGEvent` 确实在工作 —— `NSEvent.mouseLocation` 返回了更新后的坐标
2. X 坐标几乎精确匹配，Y 坐标差 300-400 像素
3. 用户说"还是没动" —— 可见光标没移动

### 关键日志（2026-05-28 12:58 最新版本）

```
screen.frame=(0.0, 0.0, 1470.0, 956.0), tip.y=0.7691
finalCursor=(708.66, 291.75)          ← 传给 CGEvent
mouseLocation after=(699.09, 633.84)  ← NSEvent 读取的位置
```

X 差了 ~9 像素（平滑导致），Y 差了 ~342 像素。

### 问题本质

```
target y = 291.75 (从底部算, NSScreen 坐标系)
actual y = 633.84 (从底部算, NSEvent 坐标系)
```

`CGEvent.location` 使用 **top-left 原点**坐标（Quartz 坐标系），而我们传的是 **bottom-left 原点**（NSScreen 坐标系）。

### 但是...还有一个更深的问题

即使在 `moveCursor` 里做 y 翻转，用户仍然说"还是没动"。这意味着即使 CGEvent 更新了 `NSEvent.mouseLocation` 属性，**macOS 26 的可见光标可能不响应 `.mouseMoved` 事件**。

## 推荐修复方案

### 方案一：CGWarp + CGAssociate（推荐）

恢复使用 `CGWarpMouseCursorPosition`，这是唯一保证移动可见光标的 API。

```swift
func moveCursor(to point: CGPoint) {
    CGAssociateMouseAndMouseCursorPosition(true)  // 接管光标控制
    CGWarpMouseCursorPosition(point)               // 移动光标
}
```

### 方案二：CGWarp 单独用

如果方案一不生效，尝试只调 `CGWarpMouseCursorPosition`（不调 CGAssociate）。

### 方案三：CGWarp + CGEvent.post (cghidEventTap) 分开

先 CGWarp，然后 CGEvent 用 `.mouseMoved`（让其他 App 接收到事件）。

## 改动的文件

只改 `Sources/MotionControl/Control/MouseController.swift` 的 `moveCursor(to:)` 方法。

## 人员分工

**小明（我）**: 分析根因、出方案
**老板（你）**: 审批方案 + 通过 Aider 执行代码改动（我改不了代码，只能你批）

## 状态

- [x] 方案待审批
- [x] 代码待执行（✅ 已确认）
- [x] 编译验证 ✅
- [ ] 运行验证（✅ 已确认，待软件启动后验证）
