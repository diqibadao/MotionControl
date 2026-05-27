# MotionControl 🖐️

> 手势 + 人脸 + 语音 三合一电脑控制系统 — macOS 原生 App

基于计算机视觉的免触控电脑操控系统，通过普通 USB 摄像头（罗技 C920e）实现：

- 🖐️ **手势识别** — 控制鼠标移动、点击、滚动、拖拽
- 👀 **注视定位** — 眼睛看哪里，光标跟到哪里
- 👄 **语音输入** — 张嘴即说，闭嘴即输，全自动

全程不用键盘、不用鼠标、不用触摸板。

---

## 技术栈

| 模块 | 技术 | 来源 | 说明 |
|------|------|------|------|
| UI 框架 | SwiftUI + AppKit | ✅ 系统原生 | 现代化声明式 UI |
| 手部检测 | Vision Framework (`VNDetectHumanHandPoseRequest`) | ✅ 系统原生 | 21 个手部关键点 |
| 人脸/嘴型 | Vision Framework (`VNDetectFaceLandmarksRequest`) | ✅ 系统原生 | 76 个面部关键点 |
| 注视估计 | Vision 头部姿态 + 眼睑轮廓推算 | ✅ 系统原生 | 无 TrueDepth 的替代方案 |
| 语音识别 | `SFSpeechRecognizer` | ✅ 系统原生 | 持续中文语音输入 |
| 鼠标/键盘控制 | Core Graphics `CGEvent` | ✅ 系统原生 | 真·系统级事件 |
| 权限管理 | 系统授权弹窗 | ✅ 系统原生 | 摄像头 + 麦克风 + 辅助功能 |

**零第三方依赖**，纯原生 macOS App，App Store 审核友好。

---

## 功能清单

### P0 — 核心功能（MVP 必备）

- [ ] 摄像头实时采集（AVCaptureSession + AVCaptureVideoDataOutput）
- [ ] 手部 21 关键点实时检测（Vision Framework）
- [ ] 6 种手势识别：张开、抓取、点头、剪刀手、握拳、滑动手势
- [ ] 手势 → 鼠标动作映射（CGEvent 系统级）
- [ ] 手势 → 键盘快捷键映射（CGEvent 系统级）
- [ ] 自主虚拟光标显示（手势位置实时跟随）
- [ ] 全手势配置化（可自定义映射）

### P1 — 增强功能

- [ ] 人脸 76 关键点实时检测（Vision Framework）
- [ ] 眼睛注视位置估算（基于眼睑轮廓 + 头部姿态）
- [ ] 注视光标显示（与手势光标区分）
- [ ] 嘴型检测（张嘴/闭嘴判定，带滞回防抖）
- [ ] 张嘴 → 自动开启语音识别
- [ ] 闭嘴 → 自动停止语音识别 + 文字提交
- [ ] 语音转文字输入到当前激活应用

### P2 — 体验优化

- [ ] 系统托盘图标（MenuBarExtra）
- [ ] 窗口悬浮模式（画中画摄像头预览）
- [ ] 全局热键开关
- [ ] 检测状态实时显示
- [ ] 配置面板（手势映射编辑 / 灵敏度调节 / 阈值设定）

### P3 — 上架准备

- [ ] Sandbox 配置
- [ ] 隐私权限描述文案（摄像头 / 麦克风 / 辅助功能）
- [ ] App 图标 + 启动画面
- [ ] 用户引导页
- [ ] 沙盒签名 + 公证

---

## 硬件要求

- **最低**：任意 USB/内置摄像头，macOS 14.0+，Apple Silicon / Intel
- **推荐**：罗技 C920e / C920s（支持 640×480 @ 30fps light）
- **备注**：无 TrueDepth 传感器时，注视精度约为屏幕 1/6 区域级别（足够定位输入框）

---

## 项目结构

```
MotionControl/
├── App/
│   ├── MotionControlApp.swift       # App 入口 + MenuBarExtra
│   └── ContentView.swift           # 主视图（摄像头预览 + 状态）
├── Camera/
│   ├── CameraService.swift         # AVCaptureSession 管理
│   └── VideoFrame.swift            # 视频帧模型
├── Detection/
│   ├── HandPoseDetector.swift      # 手部 21 关键点检测
│   ├── FaceMeshDetector.swift      # 人脸/嘴型/眼睑 76 点检测
│   ├── GestureAnalyzer.swift       # 手势分析引擎（15 种手势）
│   └── GazeEstimator.swift         # 注视点估算（瞳孔 + 头部姿态）
├── Control/
│   ├── MouseController.swift       # CGEvent 鼠标/滚动控制
│   ├── KeyboardController.swift    # CGEvent 键盘/快捷键控制
│   └── CursorOverlay.swift         # 自定义光标悬浮窗（手势+注视）
├── Voice/
│   ├── VoiceRecognizer.swift       # SFSpeechRecognizer 封装
│   └── VoiceInputManager.swift     # 嘴型→语音→文字输入流程
├── Config/
│   ├── GestureConfig.swift         # 配置数据模型（可编码）
│   ├── ConfigManager.swift         # 配置管理（读写/切换/热加载）
│   └── DefaultMappings.swift       # 默认手势映射表
├── Views/
│   ├── StatusPanel.swift           # 实时状态面板
│   ├── ConfigPanel.swift           # 配置面板（三页 Tab）
│   ├── GestureMappingView.swift    # 手势映射编辑页
│   ├── DetectionParamsView.swift   # 检测参数页
│   ├── VoiceSettingsView.swift     # 语音设置页
│   ├── GesturePicker.swift         # 手势选择器组件
│   ├── ActionPicker.swift          # 动作选择器组件
│   ├── CameraPreview.swift         # Metal 摄像头实时渲染
│   └── OnboardingView.swift        # 首次使用引导页
├── Extensions/
│   └── CGEvent+Gestures.swift      # CGEvent 便捷扩展方法
└── Resources/
    ├── Assets.xcassets             # 图标 + SF Symbols 引用
    ├── Info.plist                  # 权限描述 + Sandbox 配置
    └── DefaultConfig.json          # 出厂默认配置
```
