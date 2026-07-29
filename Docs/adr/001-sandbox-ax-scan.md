# ADR-001：沙盒 App 通过独立进程 + UNIX Socket 实现 AX 扫描

- 状态：已采纳
- 日期：2026-07-29
- 影响：MotionControl App Store 版（沙盒）AX 元素扫描、构建脚本、entitlements

## 背景

MotionControl 的"界面元素吸附"功能依赖 Accessibility API 枚举其它 App 的 UI 元素（按钮、文本框等），从而让手势光标自动对齐。

App Store 强制 App 开启沙盒（`com.apple.security.app-sandbox`），开启后：

- `AXUIElementCreateApplication(pid)` 在跨进程调用时被内核拒绝（返回错误，且不返回任何元素）
- 同一进程内（自己的 PID）AX 仍可工作
- 即使用户授予了"辅助功能"权限，沙盒边界依然优先

经验证，沙盒 App 直接调 AX 扫描 → `raw=0 visible=0`，功能完全失效。

## 决策

把 AX 扫描拆到一个**独立的非沙盒进程 `AXHelper`**，主 App 通过 UNIX Socket 与之通信：

```
┌─────────────────────────────────────┐
│ MotionControl.app (沙盒)            │
│  - UIElementScanner.swift           │
│  - CGWindowList 拿窗口列表（沙盒 OK）│
│  - 把窗口列表通过 socket 发出去      │
│  - 收到 ElementDTO 列表做吸附       │
└──────────┬──────────────────────────┘
           │ AF_UNIX SOCK_STREAM
           │ ~/Library/Containers/.../tmp/axhelper.sock
┌──────────▼──────────────────────────┐
│ AXHelper (无沙盒)                   │
│  - launchctl asuser 启动 (用户身份) │
│  - LaunchAgent 守护 (KeepAlive)     │
│  - 收到窗口列表 → AX 扫描 → 返回    │
└─────────────────────────────────────┘
```

关键约束：

1. **Socket 必须在 App 沙盒容器内**：`~/Library/Containers/com.motioncontrol.app/Data/tmp/axhelper.sock`。沙盒 App 无法访问 `/tmp` 等容器外路径。
2. **AXHelper 必须以 console user 身份启动**：`launchctl asuser $UID launchctl bootstrap`。root 启动的 socket 沙盒 App（同 UID 用户）连不上。
3. **Socket 权限设为 0666**：`chmod(socketPath, 0o666)`。LaunchAgent 启动后 socket 默认权限不让其它 UID 读写。
4. **两个 binary 必须分别签 entitlements**：AXHelper 空 entitlements（无沙盒），MotionControl 标准沙盒 entitlements。最后签 bundle 时加 `--preserve-metadata=entitlements`，否则内嵌 binary 的 entitlements 会被覆盖。

## 备选方案

### A. 直接用 XPC Service

把 AXHelper 做成 App 内的 `XPCService`，被主 App 通过 `NSXPCConnection` 调用。

- **优点**：系统级支持，沙盒友好
- **缺点**：Swift `@objc` protocol 在跨进程 XPC 下签名/反射异常，本项目实测触发 SIGSEGV；调试成本远高于 UNIX Socket

### B. 用 NSAppleScript / System Events 间接触发扫描

让 AXHelper 通过 AppleScript 调用 System Events 做扫描。

- **优点**：不用自己处理 entitlements
- **缺点**：性能差（AppleScript 启动开销 ~200ms），扫描深度受限，无法枚举 Dock/SystemUIServer

### C. 用 App Group + 共享文件传递扫描请求

- **优点**：看起来简单
- **缺点**：轮询延迟高、不可行（AX 扫描必须同步返回结果）

## 结果

- ✅ 沙盒 App 内 `raw=121, visible=103`（4 窗口 / 4 PID）
- ✅ 用户授予辅助功能权限后 AXHelper 正常工作
- ✅ App Store 版 PKG 0.9.1 可安装、可启动、扫描有效
- ⚠️ postinstall 脚本必须正确识别 console user，否则 AXHelper 无法被主 App 连接
- ⚠️ 两个 binary 的 entitlements 必须分别签，bundle 重签时 `--preserve-metadata=entitlements` 不能忘

## 后续

- macOS 后续版本如放开跨进程 AX 调用，可考虑回收独立进程
- 任何跨进程 IPC 改动都要先检查 socket 路径是否落在沙盒容器内

## 参考

- 关键文件：
  - `Sources/AXHelper/main.swift` — UNIX Socket 服务端
  - `Sources/MotionControl/Control/UIElementScanner.swift` — 客户端 + CGWindowList
  - `scripts/build_pkg.sh` — PKG 构建（含 postinstall + LaunchAgent 部署）
  - `build/Entitlements.plist` — 主 App 沙盒 entitlements
  - `build/Entitlements-NoSandbox.plist` — AXHelper 空 entitlements