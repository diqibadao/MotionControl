# MotionControl App Store 上架流程

## 一、证书申请

### 1.1 生成 CSR（证书签名请求）
```bash
# 生成私钥（所有证书共用）
openssl genrsa -out distribution_private.key 2048

# 生成 CSR
openssl req -new -key distribution_private.key -out request.certSigningRequest -subj "/CN=你的名字"
```

### 1.2 在 Apple Developer 网站创建证书
前往 https://developer.apple.com/account/resources/certificates/list

| 序号 | 证书名称 | 用途 |
|------|---------|------|
| 1 | Developer ID Application | DMG/官网分发（不用上 App Store 可不申请） |
| 2 | Mac App Distribution | 签 .app 二进制 |
| 3 | Mac Installer Distribution | 签 .pkg 安装包 |

每个证书上传同一个 `request.certSigningRequest`，下载 `.cer` 文件。

### 1.3 导入证书到钥匙串
```bash
# 证书转 PEM
openssl rsa -in distribution_private.key -out dist_key.pem

# 制作 p12 包（证书 + 私钥配对）
openssl pkcs12 -export -inkey dist_key.pem -in 证书文件.cer -out bundle.p12 -passout pass:mc123

# 导入钥匙串
security import bundle.p12 -k ~/Library/Keychains/login.keychain-db -P mc123 -A

# 验证
security find-identity -v -p codesigning
```

---

## 二、构建 & 签名

### 2.1 准备工作
确保以下文件存在且正确：
- `Sources/MotionControl/Info.plist` 包含：
  - `CFBundleIdentifier`: `com.motioncontrol.app`
  - `LSApplicationCategoryType`: `public.app-category.utilities`
  - `LSMinimumSystemVersion`: `14.0`
  - `ITSAppUsesNonExemptEncryption`: `false`
  - `NSCameraUsageDescription`
- `build/Entitlements.plist` 包含：
  - `com.apple.security.app-sandbox`: `true`
  - `com.apple.security.device.camera`: `true`

### 2.2 构建
```bash
swift build -c release
```

### 2.3 部署到 .app bundle
```bash
cp .build/arm64-apple-macosx/release/MotionControl build/MotionControl.app/Contents/MacOS/
cp .build/arm64-apple-macosx/release/AXHelper build/MotionControl.app/Contents/MacOS/

# 资源文件
mkdir -p build/MotionControl.app/Contents/Resources
cp Localizable.json build/MotionControl.app/Contents/Resources/
cp AppIcon.icns build/MotionControl.app/Contents/Resources/
```

### 2.4 签名（用证书哈希，避免重名冲突）
```bash
# 获取证书哈希
security find-identity -v -p basic | grep "3rd Party Mac"

# Mac App Distribution 签名 .app
codesign --force --sign "证书哈希" \
  --entitlements build/Entitlements.plist \
  build/MotionControl.app/Contents/MacOS/MotionControl

codesign --force --sign "证书哈希" \
  --entitlements build/Entitlements.plist \
  build/MotionControl.app/Contents/MacOS/AXHelper

codesign --force --sign "证书哈希" \
  --preserve-metadata=entitlements \
  build/MotionControl.app
```

### 2.5 打包 .pkg
```bash
# 组件打包
productbuild --component build/MotionControl.app /Applications \
  --sign "Mac Installer Distribution 证书哈希" \
  build/MotionControl.pkg
```

### 2.6 创建 .itmsp 提交包
```bash
mkdir -p MotionControl.itmsp
cp build/MotionControl.pkg MotionControl.itmsp/

# 生成 metadata.xml
FILESIZE=$(stat -f%z MotionControl.itmsp/MotionControl.pkg)
MD5=$(md5 -q MotionControl.itmsp/MotionControl.pkg)

cat > MotionControl.itmsp/metadata.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://apple.com/itunes/importer" version="software5.4">
    <software_assets>
        <asset type="bundle">
            <data_file>
                <file_name>MotionControl.pkg</file_name>
                <size>$FILESIZE</size>
                <checksum type="md5">$MD5</checksum>
            </data_file>
        </asset>
    </software_assets>
</package>
EOF
```

### 2.7 上传到 App Store Connect
**方式 A：Transporter CLI**
```bash
/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter \
  -m upload \
  -u "你的AppleID@邮箱.com" \
  -p "app-specific-password" \
  -f MotionControl.itmsp \
  -itc_provider 你的TeamID
```

**方式 B：Transporter GUI**
- 打开 Transporter App
- 登录 Apple ID
- 拖 `MotionControl.itmsp` 文件夹进去
- 点"交付"

---

## 三、App Store Connect 设置

### 3.1 注册 Bundle ID
前往 https://developer.apple.com/account/resources/identifiers/list
- 点 `+` → App IDs → macOS
- Bundle ID: `com.motioncontrol.app`

### 3.2 创建 App 记录
前往 https://appstoreconnect.apple.com → 我的 App → `+` 新建 App
- 平台: macOS
- 名称: MotionControl
- 主要语言: Simplified Chinese
- Bundle ID: com.motioncontrol.app
- SKU: MC001
- 用户访问权限: 完全访问

### 3.3 App 信息
- 主要类别: 工具（Utilities）
- 内容版权: `2026 你的名字`
- 年龄分级: 4+
- 隐私政策 URL: `https://github.com/你的用户名/MotionControl#privacy`

### 3.4 macOS App 版本 1.0
| 字段 | 内容 |
|------|------|
| 推广文本 | 通过手势和面部识别，无需触碰键盘鼠标即可操控Mac。专为行动不便用户设计。支持捏合点击、滑动滚轮、光标跟随。 |
| 描述 | 辅助功能工具描述（参考 README） |
| 关键词 | 手势控制,光标控制,免触控,辅助功能,手部追踪,摄像头鼠标 |
| 技术支持网址 | `https://github.com/你的用户名/MotionControl` |
| 营销网址 | `https://github.com/你的用户名/MotionControl#readme` |
| 版本 | 1.0 |
| 版权 | 2026 你的名字 |

### 3.5 App 沙盒信息
- 权限密钥: `com.apple.security.device.camera`
- 使用信息: 需要使用摄像头进行手部姿态识别实现手势控制

### 3.6 App 加密文稿
选择：**不属于上述的任意一种算法**（不用加密）

### 3.7 App 审核信息
- 登录信息: 不需要（关闭开关）
- 备注: 填写辅助功能说明、权限说明、沙盒例外说明（参考之前的备注模板）

### 3.8 定价
免费

### 3.9 截屏
- 至少 1 张，最多 10 张
- 尺寸: 1280×800 / 1440×900 / 2560×1600 / 2880×1800
- 建议: 使用 sips 命令缩放

### 3.10 App 隐私
填写数据收集声明（本 App 不收集任何数据）

---

## 四、提交审核

1. 等待构建处理完成（约 5-15 分钟）
2. macOS App 版本 1.0 → 构建版本 → 选择上传的构建
3. 确认所有必填项已完成（无红色提示）
4. 点右上角"添加以供审核"

---

## 五、审核等待

- 通常 1-3 天
- 如有问题 Apple 会在 App Store Connect 发消息
- 可在"App 审核"页面查看状态和回复

---

## 六、审核被拒记录

### 2026-07-20 第一轮审核（Submission ID: cdb9372b）

**Guideline 5.2.5 — App 副标题含 "Mac"**
- 原因：App Store Connect 副标题中包含了 "Mac" 字样，Apple 认为与自家商标混淆
- 修复：修改副标题，去掉 "Mac"，改用描述 App 功能的表述（如"手势控制 & 语音识别"）

**Guideline 2.3.6 — 年龄分级误选了 In-App Controls**
- 原因：年龄分级问卷中勾选了"家长控制"或"年龄保证"，但 App 没有这些功能
- 修复：在 App Store Connect > App 信息 > 年龄分级中，将 "Parental Controls" 和 "Age Assurance" 均设为 "None"

**Guideline 2.1 — 需说明辅助功能权限请求位置**
- 原因：审核员找不到辅助功能权限的请求入口
- 说明：权限在 App 主界面加载时自动触发（`.task` → `PermissionManager.checkAll()` → `checkAccessibility()`），首次未授权时 macOS 自动弹出系统对话框引导用户前往「系统设置 > 隐私与安全性 > 辅助功能」
- 注意：回复审核员时需完整说明触发路径，不能用"自动触发"一句话带过

### 提审前检查清单
- [ ] 副标题不含 Apple 商标词汇（Mac、iPhone、iPad、Apple 等）
- [ ] 年龄分级问卷逐项核对，不确定的都选"无"
- [ ] 所有系统权限请求的触发路径能清楚描述给审核员
- [ ] `ITSAppUsesNonExemptEncryption` 已在 Info.plist 中设为 `false`

---

## 七、常见问题

| 问题 | 解决 |
|------|------|
| `unsealed contents present in the bundle root` | 签名时忽略，不影响上传 |
| `Could not find an application record` | 确认 App Store Connect 已创建 macOS App + Bundle ID 匹配 |
| `App sandbox not enabled` | Entitlements 必须包含 `com.apple.security.app-sandbox=true` |
| `Missing LSApplicationCategoryType` | Info.plist 加 `LSApplicationCategoryType: public.app-category.utilities` |
| `arm64 but not Intel` | Info.plist 加 `LSMinimumSystemVersion: 14.0` |
| `ITSAppUsesNonExemptEncryption` | Info.plist 加 `ITSAppUsesNonExemptEncryption: false` |
| Transporter GUI 报 ITMSP 错误 | 拖的是 `.itmsp` 文件夹（不是 `.pkg` 文件） |
| 每次重建 AX 权限失效 | 用 Developer ID 证书签名不换身份；或授权后不再重建 |
