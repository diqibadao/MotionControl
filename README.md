# MotionControl 🖐️

> 手势 + 人脸 + 注视 三合一电脑控制系统 — macOS 原生 App

基于计算机视觉的免触控电脑操控系统，通过普通 USB 摄像头实现：

- 🖐️ **手势识别** — 食指单击/双击/双指按下/上挥/下挥 → 鼠标动作
- 👀 **头手融合光标控制** — 头部偏转做方向修正 + 指尖精确定位
- 👄 **语音输入** — 张嘴即说，闭嘴即输

全程不用键盘、不用鼠标、不用触摸板。

---

## 技术栈

| 模块 | 技术 | 来源 | 说明 |
|------|------|------|------|
| UI 框架 | SwiftUI + AppKit | ✅ 系统原生 | 现代化声明式 UI |
| 手部检测 | Vision Framework (`VNDetectHumanHandPoseRequest`) | ✅ 系统原生 | 21 个手部关键点 |
| 人脸/嘴型 | Vision Framework (`VNDetectFaceLandmarksRequest`) | ✅ 系统原生 | 76 个面部关键点 |
| 头部姿态 | Vision 头部欧拉角（yaw/pitch/roll） | ✅ 系统原生 | 无 TrueDepth 的替代方案 |
| 手势检测 | 指尖时间序列分析（tap/double-tap/swipe） | ✅ 自研 | 滑动窗口 + 阈值判定 |
| 光标控制 | 指尖定位 + 头部偏移修正 | ✅ 自研 | 头手融合模型 |
| 鼠标/键盘控制 | Core Graphics `CGEvent` | ✅ 系统原生 | 真·系统级事件 |
| 权限管理 | 系统授权弹窗 | ✅ 系统原生 | 摄像头 + 麦克风 + 辅助功能 |

**零第三方依赖**，纯原生 macOS App。

---

## 功能清单

### P0 — 核心功能

- [x] 摄像头实时采集（AVCaptureSession + AVCaptureVideoDataOutput）
- [x] 手部 21 关键点实时检测（Vision Framework）
- [x] **时间序列手势检测**：食指单击、食指双击、双指按下（拖拽）、双指收回、上挥、下挥
- [x] **头手融合光标控制**：头部偏转方向修正 + 指尖精确定位
- [x] **纯手指光标模式**：关闭注视追踪时指尖直接控制光标
- [x] 手势 → 鼠标动作映射（CGEvent 系统级：单击/双击/拖拽/滚动）
- [x] **手势映射可配置**：每个手势可绑定不同动作（下拉选择）
- [x] 摄像头叠加层 — 手部 21 点 + 面部 76 点实时标识
- [x] 手部骨骼连线（白色半透明）
- [x] 识别状态文字叠加显示（FPS / 手势 / 嘴型）
- [x] 检测参数面板：手势灵敏度 / 鼠标速度 / 注视灵敏度 / 注视追踪开关

### P1 — 增强功能

- [x] 人脸 76 关键点实时检测（Vision Framework）
- [x] **头部自动标定**：启动后自动收集姿态基线，适配摄像头位置
- [x] 注视追踪方向指示（画面十字准心）
- [x] 嘴型检测（张嘴/闭嘴判定，带滞回防抖）
- [x] 命令触发时识别点位变红 1 秒反馈
- [ ] 张嘴 → 自动开启语音识别
- [ ] 闭嘴 → 自动停止语音识别 + 文字提交
- [ ] 语音转文字输入到当前激活应用

### P2 — 体验优化

- [ ] 系统托盘图标（MenuBarExtra）
- [ ] 窗口悬浮模式（画中画摄像头预览）
- [ ] 全局热键开关
- [x] 检测状态实时显示（视频画面左上角叠加）
- [x] 配置面板（手势映射编辑 + 检测参数调节）

### P3 — 上架准备

- [ ] Sandbox 配置
- [ ] 隐私权限描述文案（摄像头 / 麦克风 / 辅助功能）
- [ ] App 图标 + 启动画面
- [ ] 用户引导页
- [ ] 沙盒签名 + 公证

---

## 手势映射说明

| 手势 | 检测方式 | 默认动作 | 可配置 |
|------|---------|---------|--------|
| **食指单击** | indexTip.y 快速下降再回升 | 左键单击 | ✅ |
| **食指双击** | 两次单击间隔 < 400ms | 左键双击 | ✅ |
| **双指按下** | indexTip + middleTip 同时下降 | 拖拽开始 | ✅ |
| **双指收回** | 双指同时回升 | 拖拽结束 | ✅ |
| **上挥** | 手掌中心（wrist.y）持续下降 | 内容上滚 | ✅ |
| **下挥** | 手掌中心（wrist.y）持续上升 | 内容下滚 | ✅ |

---

## 硬件要求

- **最低**：任意 USB/内置摄像头，macOS 14.0+，Apple Silicon / Intel
- **推荐**：罗技 C920e / C920s（支持 640×480 @ 30fps）
- **备注**：注视追踪基于头部姿态（非瞳孔追踪），定位精度为方向级修正

---

## 项目结构

```
MotionControl/
├── App/
│   ├── MotionControlApp.swift     # App 入口 + 主视图
│   ├── SystemState.swift          # 全局可观察状态
│   └── EventLogger.swift          # 事件日志系统
├── Camera/
│   └── CameraService.swift        # AVCaptureSession 管理
├── Detection/
│   ├── HandPoseDetector.swift     # 手部 21 关键点检测
│   ├── FaceMeshDetector.swift     # 人脸/嘴型/眼睑 76 点检测
│   ├── MouthDetector.swift        # 嘴型开合检测
│   ├── GestureAnalyzer.swift      # 时间序列手势分析引擎
│   ├── GazeEstimator.swift        # 头部姿态偏移 + 自动标定
│   └── DetectionPipeline.swift    # 检测管道调度
├── Control/
│   ├── MouseController.swift      # CGEvent 鼠标/滚动控制
│   ├── KeyboardController.swift   # CGEvent 键盘控制
│   └── CursorController.swift     # 头手融合光标计算
├── Voice/
│   ├── VoiceRecognizer.swift      # SFSpeechRecognizer 封装
│   ├── VoiceInputManager.swift    # 嘴型→语音→文字流程
│   └── TextInjector.swift         # 文字注入
├── Config/
│   ├── GestureConfig.swift        # 配置数据模型（可编码）
│   ├── ConfigManager.swift        # 配置读写/热加载
│   └── GestureConfig.swift        # 手势类型/动作类型/映射
├── Views/
│   ├── CameraPreviewView.swift    # 摄像头预览 + 叠加绘制
│   ├── CameraOverlayView.swift    # 手脸识别点位叠加层
│   ├── StatusPanelView.swift      # 实时状态面板
│   ├── ConfigPanelView.swift      # 配置面板（三页 Tab）
│   ├── GestureMappingView.swift   # 手势映射编辑页（选中/修改）
│   ├── DetectionParamsView.swift  # 检测参数页（灵敏度滑条）
│   ├── VoiceSettingsView.swift    # 语音设置页
│   └── ConfigTestView.swift       # 调试信息页
└── Resources/
    ├── Info.plist                 # 权限描述
    └── DefaultConfig.json         # 出厂默认配置
```

---

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| v0.2 | 2026-05-27 | 头手融合光标控制 + 时间序列手势 + 手势映射可配置 |
| v0.1 | 2026-05-27 | 手/脸点位标识准确、嘴巴张合准确（基线版本）|
