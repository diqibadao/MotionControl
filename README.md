# MotionControl

> 基于计算机视觉的辅助功能工具 — 通过手势操控 Mac

MotionControl 是一款 macOS 辅助功能应用，通过普通摄像头实现免触控电脑操控，专为行动不便的用户设计。

## 核心功能

- **手势控制光标** — 手指移动即可控制鼠标指针
- **捏合点击** — 拇指与食指捏合 = 左键单击
- **捏合滚动** — 捏合后上下移动手掌即可滚动
- **界面元素吸附** — 自动检测按钮与输入框，光标自动吸附对齐

## 适用人群

- 手部/手臂行动不便的用户
- 需要减少重复性劳损的用户
- 追求更自然交互方式的用户

## 系统要求

- macOS 14.0 (Sonoma) 或更高
- 任意 USB 或内置摄像头
- 需要授予摄像头和辅助功能权限

## 安装

- **GitHub 版**：从 [Releases](https://github.com/diqibadao/MotionControl/releases) 下载 DMG
- **App Store 版**：App Store 搜索 MotionControl

## 技术栈

Swift 5.9 / SwiftUI + AppKit + Vision Framework + Core Graphics

零第三方依赖，纯原生 macOS API。

## 隐私

- 所有视频处理在本地完成
- 不收集、不上传任何用户数据
- 不需要网络连接

## 文档

- **CHANGELOG.md** — 版本日志（自动生成）
- **[Docs/adr/](Docs/adr/)** — 重要技术决策记录
- **[Docs/](Docs/)** — 需求文档 / 技术方案 / 质量标准
- 内联代码注释 — 关键逻辑解释

## 贡献

开发分支：`feat/*` 或 `fix/*`，完成后 PR 到 `main`。

两个发布版本：
- `main` — GitHub 版（无沙盒，DMG）
- `appstore` — App Store 版（沙盒，PKG）

代码改动同时在两边生效。

## 开发者

```bash
# 编译
swift build -c release

# 打包 GitHub 版（DMG）
bash scripts/build_github.sh

# 打包 App Store 版（PKG）
bash scripts/build_appstore.sh
```

更多构建细节见 `scripts/` 下的脚本。
