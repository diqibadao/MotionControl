import Cocoa
import SwiftUI

/// 菜单栏控制器：NSStatusBar + 药丸图标 + NSMenu
/// 100% 还原原型设计
final class MenuBarController: NSObject {
    static let shared = MenuBarController()
    private var statusItem: NSStatusItem?
    
    var text: String = "空闲"
    var isGreen: Bool = false
    var gestureEnabled: Bool = true
    var cursorEnabled: Bool = true
    var cameraEnabled: Bool = true
    var onDebugWindow: (() -> Void)?
    var onQuit: (() -> Void)?
    private var pillWidth: CGFloat = 0
    
    // MARK: - Lifecycle
    
    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.imagePosition = .imageOnly
        renderPill()
        statusItem?.length = pillWidth
        statusItem?.menu = buildMenu()
    }
    
    func stop() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }
    
    func refresh(text: String, isGreen: Bool) {
        self.text = text
        self.isGreen = isGreen
        DispatchQueue.main.async { self.renderPill() }
    }
    
    // MARK: - Pill rendering
    
    private func renderPill() {
        guard let button = statusItem?.button else { return }
        
        // 原型 CSS 参数
        let pillH: CGFloat = 24
        let padLeft: CGFloat = 3
        let padRight: CGFloat = 6
        let gap: CGFloat = 5
        let dotGap: CGFloat = 6
        let iconSize: CGFloat = 17
        let dotSize: CGFloat = 6
        
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let displayText: String = {
            switch text {
            case "空闲": return AppLanguage.shared.t("pill.idle")
            case "就绪": return AppLanguage.shared.t("pill.ready")
            case "移动": return AppLanguage.shared.t("pill.move")
            case "点击": return AppLanguage.shared.t("pill.click")
            case "滚动": return AppLanguage.shared.t("pill.scroll")
            default: return text
            }
        }()
        let textW = (displayText as NSString).size(withAttributes: [.font: font]).width
        let pillW = padLeft + iconSize + gap + textW + dotGap + dotSize + padRight
        
        let image = NSImage(size: NSSize(width: pillW, height: pillH))
        image.lockFocus()
        
        // ── 手形图标：原型 SVG 路径逐坐标转换 ──
        let sx = padLeft
        let sy: CGFloat = (pillH - iconSize) / 2
        let scale = iconSize / 24.0  // 原型 viewBox 0 0 24 24
        
        func px(_ x: CGFloat) -> CGFloat { sx + x * scale }
        func py(_ y: CGFloat) -> CGFloat { sy + y * scale }
        
        NSGraphicsContext.current?.saveGraphicsState()
        // 白色投影
        let handShadow = NSShadow()
        handShadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
        handShadow.shadowBlurRadius = 1.5
        handShadow.shadowOffset = NSSize(width: 0, height: -1)
        handShadow.set()
        NSColor.white.setStroke()
        
        // 路径1：手掌 + 食指（原型 stroke-width:1.85）
        let hand = NSBezierPath()
        hand.move(to: NSPoint(x: px(8.6), y: py(13.9)))
        hand.line(to: NSPoint(x: px(5.4), y: py(11)))
        hand.curve(to: NSPoint(x: px(5.3), y: py(8.5)),
                   controlPoint1: NSPoint(x: px(4.6), y: py(10.3)),
                   controlPoint2: NSPoint(x: px(4.6), y: py(9.2)))
        hand.curve(to: NSPoint(x: px(7.8), y: py(8.5)),
                   controlPoint1: NSPoint(x: px(6), y: py(7.8)),
                   controlPoint2: NSPoint(x: px(7), y: py(7.8)))
        hand.line(to: NSPoint(x: px(9.7), y: py(10.3)))
        hand.line(to: NSPoint(x: px(9.7), y: py(5.1)))
        hand.curve(to: NSPoint(x: px(11.5), y: py(3.3)),
                   controlPoint1: NSPoint(x: px(9.7), y: py(4.1)),
                   controlPoint2: NSPoint(x: px(10.5), y: py(3.3)))
        hand.curve(to: NSPoint(x: px(13.3), y: py(5.1)),
                   controlPoint1: NSPoint(x: px(12.5), y: py(3.3)),
                   controlPoint2: NSPoint(x: px(13.3), y: py(4.1)))
        hand.line(to: NSPoint(x: px(13.3), y: py(11.2)))
        hand.line(to: NSPoint(x: px(14.2), y: py(10.1)))
        hand.curve(to: NSPoint(x: px(16.7), y: py(9.7)),
                   controlPoint1: NSPoint(x: px(14.8), y: py(9.3)),
                   controlPoint2: NSPoint(x: px(15.9), y: py(9.1)))
        hand.curve(to: NSPoint(x: px(17), y: py(12.2)),
                   controlPoint1: NSPoint(x: px(17.5), y: py(10.3)),
                   controlPoint2: NSPoint(x: px(17.6), y: py(11.4)))
        hand.line(to: NSPoint(x: px(13.6), y: py(16.9)))
        hand.curve(to: NSPoint(x: px(9.1), y: py(18.7)),
                   controlPoint1: NSPoint(x: px(12.8), y: py(18)),
                   controlPoint2: NSPoint(x: px(10.1), y: py(18.7)))
        hand.lineWidth = 1.85 * scale
        hand.lineCapStyle = .round
        hand.lineJoinStyle = .round
        hand.stroke()
        
        // 路径2+3：信号线（原型 stroke-width:1.7）
        let signal = NSBezierPath()
        signal.move(to: NSPoint(x: px(16.8), y: py(4.5)))
        signal.curve(to: NSPoint(x: px(18.7), y: py(5.7)),
                      controlPoint1: NSPoint(x: px(17.5), y: py(4.7)),
                      controlPoint2: NSPoint(x: px(18.2), y: py(5.1)))
        signal.move(to: NSPoint(x: px(18.7), y: py(2.1)))
        signal.curve(to: NSPoint(x: px(21.5), y: py(4.2)),
                      controlPoint1: NSPoint(x: px(19.8), y: py(2.5)),
                      controlPoint2: NSPoint(x: px(20.8), y: py(3.2)))
        signal.lineWidth = 1.7 * scale
        signal.lineCapStyle = .round
        signal.stroke()
        
        NSGraphicsContext.current?.restoreGraphicsState()
        
        // ── 文字（白色, 12px, weight:620 = .medium）──
        let textAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textX = padLeft + iconSize + gap
        let textY = (pillH - font.pointSize) / 2 - 1
        (displayText as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttr)
        
        // ── 圆点（原型 right:5px, top:6px, 6x6, #34c759 + 白环发光）──
        let dotX = pillW - dotSize - 5
        let dotY = pillH - dotSize - 6  // top:6px → y= pillH - 6 - 6
        if isGreen {
            // 白环（box-shadow: 0 0 0 2px rgba(255,255,255,.28)）
            NSColor.white.withAlphaComponent(0.28).setFill()
            let ringPath = NSBezierPath(ovalIn: NSRect(x: dotX - 2, y: dotY - 2, width: 10, height: 10))
            ringPath.fill()
            // 绿色实心 + 发光
            let glow = NSShadow()
            glow.shadowColor = NSColor(calibratedRed: 52/255, green: 199/255, blue: 89/255, alpha: 0.72)
            glow.shadowBlurRadius = 8
            glow.set()
            NSColor(calibratedRed: 52/255, green: 199/255, blue: 89/255, alpha: 1).setFill()
            let dotPath = NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: 6, height: 6))
            dotPath.fill()
        } else {
            // 白色实心圆
            NSColor.white.setFill()
            let dotPath = NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: 6, height: 6))
            dotPath.fill()
        }
        
        image.unlockFocus()
        image.isTemplate = false
        pillWidth = pillW
        button.image = image
        button.imagePosition = .imageOnly
    }
    
    // MARK: - Menu building
    
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // 头部标题
        let headerItem = NSMenuItem()
        headerItem.view = menuHeaderView()
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())
        
        // 全部控制
        let allItem = NSMenuItem()
        allItem.view = checkMenuItemView(title: AppLanguage.shared.t("menu.all"), isOn: gestureEnabled && cursorEnabled && cameraEnabled, action: #selector(toggleAll))
        menu.addItem(allItem)
        
        menu.addItem(.separator())
        
        // 手势控制
        let gestureItem = NSMenuItem()
        gestureItem.view = checkMenuItemView(title: AppLanguage.shared.t("menu.gesture"), isOn: gestureEnabled, action: #selector(toggleGesture))
        menu.addItem(gestureItem)
        
        // 光标控制
        let cursorItem = NSMenuItem()
        cursorItem.view = checkMenuItemView(title: AppLanguage.shared.t("menu.cursor"), isOn: cursorEnabled, action: #selector(toggleCursor))
        menu.addItem(cursorItem)
        
        // 摄像头
        let cameraToggleItem = NSMenuItem()
        cameraToggleItem.view = checkMenuItemView(title: AppLanguage.shared.t("menu.camera.toggle"), isOn: cameraEnabled, action: #selector(toggleCamera))
        menu.addItem(cameraToggleItem)
        
        // 调试设置
        let debugItem = NSMenuItem(title: AppLanguage.shared.t("menu.debug"), action: #selector(openDebug), keyEquivalent: "")
        debugItem.target = self
        menu.addItem(debugItem)
        
        // Camera 子菜单
        let cameraMenuItem = NSMenuItem(title: AppLanguage.shared.t("menu.camera"), action: nil, keyEquivalent: "")
        let cameraMenu = NSMenu()
        for cam in CameraService.availableCameras() {
            let item = NSMenuItem(title: cam.name, action: #selector(switchCamera(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = cam.id
            item.state = cam.id == CameraService.shared?.activeCameraID ? .on : .off
            cameraMenu.addItem(item)
        }
        cameraMenuItem.submenu = cameraMenu
        menu.addItem(cameraMenuItem)
        
        // 语言
        let langItem = NSMenuItem(title: AppLanguage.shared.t("menu.language"), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        let zhItem = NSMenuItem(title: AppLanguage.shared.t("menu.lang.zh"), action: #selector(switchLanguage(_:)), keyEquivalent: "")
        zhItem.target = self
        zhItem.state = AppLanguage.shared.isChinese ? .on : .off
        langMenu.addItem(zhItem)
        let enItem = NSMenuItem(title: AppLanguage.shared.t("menu.lang.en"), action: #selector(switchLanguage(_:)), keyEquivalent: "")
        enItem.target = self
        enItem.state = AppLanguage.shared.isChinese ? .off : .on
        langMenu.addItem(enItem)
        langItem.submenu = langMenu
        menu.addItem(langItem)
        
        menu.addItem(.separator())
        
        // 关于
        let aboutItem = NSMenuItem(title: AppLanguage.shared.t("menu.about"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        // 退出
        let quitItem = NSMenuItem(title: AppLanguage.shared.t("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    private func menuHeaderView() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let title = NSTextField(labelWithString: "MotionControl")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 10, y: 18, width: 180, height: 16)
        v.addSubview(title)
        
        let subtitle = NSTextField(labelWithString: gestureEnabled || cursorEnabled ? "控制已开启" : "控制已关闭")
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 10, y: 4, width: 180, height: 14)
        v.addSubview(subtitle)
        return v
    }
    
    private func checkMenuItemView(title: String, isOn: Bool, action: Selector) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let label = NSTextField(frame: NSRect(x: 15, y: 3, width: 135, height: 16))
        label.stringValue = title
        label.isBordered = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .labelColor
        v.addSubview(label)
        let mark = NSTextField(labelWithString: isOn ? "✓" : "")
        mark.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        mark.textColor = .labelColor
        mark.frame = NSRect(x: 165, y: 3, width: 20, height: 16)
        mark.alignment = .right
        v.addSubview(mark)
        let btn = NSButton(frame: v.bounds)
        btn.isBordered = false
        btn.isTransparent = true
        btn.target = self
        btn.action = action
        v.addSubview(btn)
        return v
    }
    
    private func toggleMenuItemView(title: String, isOn: Bool, action: Selector) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 212, height: 34))
        v.wantsLayer = true
        
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.frame = NSRect(x: 12, y: 8, width: 104, height: 18)
        v.addSubview(label)
        
        let button = NSButton(frame: NSRect(x: 150, y: 6, width: 48, height: 22))
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.target = self
        button.action = action
        button.wantsLayer = true
        styleToggleButton(button, isOn: isOn)
        v.addSubview(button)
        return v
    }

    private func styleToggleButton(_ button: NSButton, isOn: Bool) {
        button.title = isOn ? "启用" : "禁用"
        button.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = isOn
            ? NSColor(calibratedRed: 0.08, green: 0.36, blue: 0.63, alpha: 1)
            : NSColor.secondaryLabelColor
        button.layer?.cornerRadius = 6
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = isOn
            ? NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.0, alpha: 1).cgColor
            : NSColor(calibratedRed: 0.88, green: 0.89, blue: 0.91, alpha: 1).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = isOn
            ? NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.0, alpha: 1).cgColor
            : NSColor.black.withAlphaComponent(0.05).cgColor
    }
    
    private func updateMenuStates() {
        guard let menu = statusItem?.menu else { return }
        let states: [Bool] = [gestureEnabled && cursorEnabled && cameraEnabled,
                               gestureEnabled, cursorEnabled, cameraEnabled]
        var idx = 0
        for item in menu.items {
            for sv in item.view?.subviews ?? [] {
                if let btn = sv as? NSButton, btn.action != nil, idx < states.count {
                    if let superview = btn.superview {
                        let fields = superview.subviews.compactMap { $0 as? NSTextField }
                        if fields.count >= 2 { fields[1].stringValue = states[idx] ? "✓" : "" }
                    }
                    idx += 1
                }
            }
        }
        if let hv = menu.item(at: 0)?.view {
            for sv in hv.subviews {
                if let tf = sv as? NSTextField, tf.font?.pointSize == 11 {
                    tf.stringValue = gestureEnabled || cursorEnabled ? AppLanguage.shared.t("menu.header.running") : AppLanguage.shared.t("menu.header.stopped")
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func toggleGesture() {
        gestureEnabled.toggle()
        updateMenuStates()
    }
    
    @objc private func toggleCursor() {
        cursorEnabled.toggle()
        updateMenuStates()
    }
    
    @objc private func toggleCamera() {
        cameraEnabled.toggle()
        if cameraEnabled {
            CameraService.shared?.start()
        } else {
            CameraService.shared?.stop()
        }
        updateMenuStates()
    }
    
    @objc private func toggleAll() {
        let allOn = gestureEnabled && cursorEnabled && cameraEnabled
        gestureEnabled = !allOn
        cursorEnabled = !allOn
        if !allOn {
            CameraService.shared?.start()
            cameraEnabled = true
        } else {
            CameraService.shared?.stop()
            cameraEnabled = false
        }
        updateMenuStates()
    }
    
    @objc private func openDebug() { onDebugWindow?() }
    @objc private func quitApp() { onQuit?() }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MotionControl"
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        alert.informativeText = "v\(ver)\n\n\(AppLanguage.shared.isChinese ? "当前版本免费试用，无功能限制。\n未来版本将推出付费计划。" : "This version is free with all features.\nFuture versions will include paid plans.")"
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.runModal()
    }
    
    @objc private func switchLanguage(_ sender: NSMenuItem) {
        AppLanguage.shared.isChinese = (sender.title == AppLanguage.shared.t("menu.lang.zh"))
        statusItem?.menu = buildMenu()
        renderPill()
    }
    
    @objc private func switchCamera(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String,
              let cameraService = CameraService.shared else { return }
        cameraService.switchCamera(to: deviceID)
        // 刷新子菜单选中状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, let menu = self.statusItem?.menu else { return }
            if let cameraItem = menu.items.first(where: { $0.title == "切换摄像头" }),
               let submenu = cameraItem.submenu {
                for item in submenu.items {
                    item.state = (item.representedObject as? String) == cameraService.activeCameraID ? .on : .off
                }
            }
        }
    }
}
