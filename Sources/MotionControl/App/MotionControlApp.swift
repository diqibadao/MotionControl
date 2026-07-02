import SwiftUI
import AVFoundation
import ServiceManagement

/// MotionControl 应用入口。
/// 通过摄像头 + MediaPipe 实现手势识别、视线追踪和嘴部检测，
/// 将肢体动作映射为鼠标/键盘操作。
@main
struct MotionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = SystemState()
    
    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .onAppear {
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first(where: { $0.contentView != nil }) {
                            window.title = ""
                            window.titleVisibility = .hidden
                            window.titlebarAppearsTransparent = false
                            window.backgroundColor = NSColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1.0)
                            window.standardWindowButton(.zoomButton)?.isHidden = true
                            // 拦截关闭 → 隐藏
                            WindowHider.install(on: window)
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mb = MenuBarController.shared
        mb.onDebugWindow = {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            // 找到隐藏的窗口并显示
            for win in NSApp.windows {
                if win.isVisible { win.makeKeyAndOrderFront(nil) }
                else { win.orderFront(nil) }
            }
        }
        mb.onQuit = { NSApplication.shared.terminate(nil) }
        mb.start()
    }
}

/// 拦截窗口关闭事件，隐藏而非销毁
final class WindowHider: NSObject, NSWindowDelegate {
    static func install(on window: NSWindow) {
        let hider = WindowHider()
        window.delegate = hider
        objc_setAssociatedObject(window, "hider", hider, .OBJC_ASSOCIATION_RETAIN)
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false  // 不关闭，只隐藏
    }
}

private enum MC {
    static let ink = Color(red: 0.12, green: 0.15, blue: 0.19)
    static let muted = Color(red: 0.43, green: 0.45, blue: 0.49)
    static let quiet = Color(red: 0.62, green: 0.64, blue: 0.68)
    static let blue = Color(red: 0.02, green: 0.48, blue: 1.0)
    static let green = Color(red: 0.32, green: 0.85, blue: 0.42)
    static let window = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let sidebar = Color(red: 0.93, green: 0.94, blue: 0.95)
    static let card = Color.white.opacity(0.78)
    static let control = Color.white.opacity(0.52)
    static let hover = Color(red: 0.90, green: 0.95, blue: 1.0)
    static let line = Color.black.opacity(0.075)
    static let titlebar = Color(red: 0.96, green: 0.97, blue: 0.98)
}

private enum GestureKind: Equatable {
    case point
    case pinch
    case double
    case scroll
}

private enum InspectorTab: String, CaseIterable, Identifiable {
    case gestures = "手势"
    case settings = "设置"

    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .gestures: return AppLanguage.shared.t("tab.gestures")
        case .settings: return AppLanguage.shared.t("tab.settings")
        }
    }
}


/// 主界面，包含摄像头预览、状态叠加层和配置面板。
struct ContentView: View {
    @Bindable var state: SystemState
    
    private let cameraService = CameraService()
    private let detectionPipeline = DetectionPipeline()
    private let mouseCtrl = MouseController()
    private let keyboardCtrl = KeyboardController()
    private let cursorController = CursorController()
    private let uiScanner = UIElementScanner()
    private let debugOverlay = DebugOverlay()

    @State private var handKeypoints: [CGPoint] = []
    @State private var faceKeypoints: [CGPoint] = []
    @State private var commandTriggeredAt: Date = .distantPast
    @State private var frameGenTimer: Timer? = nil
    @State private var overlayTimer: Timer? = nil
    @State private var lostFrameCount = 0
    @State private var cursorSpeed: CGFloat = 0.62
    @State private var pinchSensitivity: CGFloat = 0.74
    @State private var doubleClickInterval: CGFloat = 0.48
    @State private var scrollNatural: Bool = true
    @State private var scrollSpeed: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "scrollSpeed")
        return v > 0 ? v : 0.4
    }()
    @State private var debugSkeleton: Bool = true
    @State private var debugOverlayEnabled: Bool = false
    @State private var debugSnap: Bool = true
    @State private var debugClickSound: Bool = false
    @State private var selectedInspectorTab: InspectorTab = .gestures
    @State private var hoveredGesture: GestureKind? = nil
    @State private var gestureAnimationPhase: Bool = false
    @State private var languageToggle: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            CameraPane()
            SidePanelView()
                .frame(width: 334)
        }
        .background(MC.window)
        .frame(width: 940, height: 500)
        .onAppear { setupPipeline() }
        .onDisappear { teardownPipeline() }
        .onChange(of: scrollSpeed) { _, newVal in
            UserDefaults.standard.set(Double(newVal), forKey: "scrollSpeed")
        }
        .task {
            AppLanguage.shared.onToggle = { languageToggle.toggle() }
            let perms = await PermissionManager.shared.checkAll()
            state.cameraGranted = perms.camera; state.micGranted = perms.mic
            state.speechGranted = perms.speech; state.accessibilityGranted = perms.accessibility
        }
    }
    
    // MARK: - Visual Components (Codex prototype)
    
    private func CameraPane() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppLanguage.shared.t("camera.preview"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.29, green: 0.32, blue: 0.36))
            }
            .frame(height: 36)

            VStack(spacing: 12) {
                ZStack {
                    CameraPreviewView(
                        session: cameraService.cameraSession,
                        handKeypoints: debugSkeleton ? handKeypoints : [],
                        faceKeypoints: debugSkeleton ? faceKeypoints : [],
                        isCommandActive: Date().timeIntervalSince(commandTriggeredAt) < 1.0,
                        frameSize: cameraService.currentFrameSize ?? .zero
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 6) {
                        HUDChip(String(format: "%.0f FPS", state.currentFPS))
                        HUDChip("\(AppLanguage.shared.t("hud.gesture")): \(state.currentGesture)")
                        HUDChip("\(AppLanguage.shared.t("hud.mode")): \(state.fingerMode)")
                        Spacer()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MC.line, lineWidth: 1)
                }
                .shadow(color: Color(red: 0.10, green: 0.15, blue: 0.20).opacity(0.07), radius: 12, y: 5)
                .frame(height: 330)

                BottomControlBar()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .overlay(alignment: .trailing) {
            Rectangle().fill(MC.line).frame(width: 1)
        }
    }

    private func BottomControlBar() -> some View {
        HStack(spacing: 8) {
            InlineToggleControl(title: AppLanguage.shared.t("toggle.skeleton"), isOn: $debugSkeleton)
            InlineToggleControl(title: AppLanguage.shared.t("toggle.uiscan"), isOn: $debugOverlayEnabled) { enabled in
                toggleDebugOverlay(enabled)
            }
            Spacer()
        }
        .padding(.horizontal, 0)
        .frame(height: 46)
    }

    private func InlineToggleControl(title: String, isOn: Binding<Bool>, onChange: ((Bool) -> Void)? = nil) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            onChange?(isOn.wrappedValue)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MC.ink)
                    .lineLimit(1)

                Text(isOn.wrappedValue ? AppLanguage.shared.t("toggle.enabled") : AppLanguage.shared.t("toggle.disabled"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? Color(red: 0.08, green: 0.36, blue: 0.63) : MC.muted)
                    .frame(width: 36, height: 20)
                    .background(isOn.wrappedValue ? Color(red: 0.88, green: 0.94, blue: 1.0) : Color(red: 0.88, green: 0.89, blue: 0.91))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 30)
            .background(Color.white.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(MC.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func InlineToggleSegment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color(red: 0.08, green: 0.36, blue: 0.63) : MC.muted)
                .frame(width: 38, height: 22)
                .background(selected ? Color.white.opacity(0.90) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: selected ? Color.black.opacity(0.10) : .clear, radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func CameraSurface() -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(red: 0.88, green: 0.90, blue: 0.92))
            .overlay { CameraGrid().opacity(0.55) }
    }

    private func CameraGrid() -> some View {
        Canvas { context, size in
            var path = Path()
            let step: CGFloat = 32
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(Color.white.opacity(0.32)), lineWidth: 1)
        }
    }

    private func HUDChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.93))
            .frame(height: 22)
            .padding(.horizontal, 8)
            .background(Color.black.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }

    private func SidePanelView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorTabs()

            Group {
                switch selectedInspectorTab {
                case .gestures:
                    GestureInspector()
                case .settings:
                    SettingsInspector()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(MC.sidebar)
    }

    private func InspectorTabs() -> some View {
        HStack(spacing: 0) {
            ForEach(InspectorTab.allCases) { tab in
                Text(tab.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedInspectorTab == tab ? MC.ink : MC.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(selectedInspectorTab == tab ? Color.white.opacity(0.88) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: selectedInspectorTab == tab ? Color.black.opacity(0.10) : .clear, radius: 1.5, y: 1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.16)) {
                            selectedInspectorTab = tab
                        }
                    }
            }
        }
        .padding(3)
        .background(Color(red: 0.55, green: 0.59, blue: 0.64).opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func GestureInspector() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GestureRef()
        }
    }

    private func SettingsInspector() -> some View {
        SettingsGroup()
    }

    private func ControlInspector() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(AppLanguage.shared.t("settings.coreParams")).padding(.top, 0)
            ParamGroup()
        }
    }

    private func DebugInspector() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(AppLanguage.shared.t("settings.debugOptions")).padding(.top, 0)
            DebugGroup()
        }
    }
    
    private func SectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MC.muted)
            .padding(.horizontal, 3)
            .padding(.top, 2)
            .padding(.bottom, 7)
    }
    
    private func GestureRef() -> some View {
        VStack(spacing: 0) {
            GestureRow(kind: .point, title: AppLanguage.shared.t("gesture.point"), subtitle: AppLanguage.shared.t("gesture.point.desc"))
            Divider().padding(.leading, 92).opacity(0.64)
            GestureRow(kind: .pinch, title: AppLanguage.shared.t("gesture.pinch"), subtitle: AppLanguage.shared.t("gesture.pinch.desc"))
            Divider().padding(.leading, 92).opacity(0.64)
            GestureRow(kind: .double, title: AppLanguage.shared.t("gesture.double"), subtitle: AppLanguage.shared.t("gesture.double.desc"))
            Divider().padding(.leading, 92).opacity(0.64)
            GestureRow(kind: .scroll, title: AppLanguage.shared.t("gesture.scroll"), subtitle: AppLanguage.shared.t("gesture.scroll.desc"))
        }
        .background(MC.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MC.line, lineWidth: 1)
        }
    }
    
    private func GestureRow(kind: GestureKind, title: String, subtitle: String) -> some View {
        let isHovered = hoveredGesture == kind

        return HStack(spacing: 16) {
            GestureGlyph(kind, isActive: isHovered, phase: gestureAnimationPhase)
                .scaleEffect(isHovered ? 1.06 : 1.0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MC.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(MC.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 15)
        .frame(height: 96.25)
        .background(isHovered ? MC.hover.opacity(0.72) : Color.clear)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hoveredGesture = kind
                gestureAnimationPhase = false
                withAnimation(.easeInOut(duration: gestureAnimationDuration(kind)).repeatForever(autoreverses: true)) {
                    gestureAnimationPhase = true
                }
            } else if hoveredGesture == kind {
                withAnimation(.easeOut(duration: 0.12)) {
                    gestureAnimationPhase = false
                    hoveredGesture = nil
                }
            }
        }
    }

    private func gestureAnimationDuration(_ kind: GestureKind) -> Double {
        switch kind {
        case .point: return 0.75
        case .pinch, .double: return 0.8
        case .scroll: return 0.9
        }
    }

    private func gestureHint(_ kind: GestureKind) -> String {
        switch kind {
        case .point: return AppLanguage.shared.t("gesture.point.hint")
        case .pinch: return AppLanguage.shared.t("gesture.pinch.hint")
        case .double: return AppLanguage.shared.t("gesture.double.hint")
        case .scroll: return AppLanguage.shared.t("gesture.scroll.hint")
        }
    }

    private func GestureGlyph(_ kind: GestureKind, isActive: Bool, phase: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MC.blue.opacity(0.09))

            Canvas { context, size in
                let blue = MC.blue
                let amount: CGFloat = isActive && phase ? 1 : 0
                func fillCapsule(_ rect: CGRect, rotation: Angle = .zero) {
                    if rotation != .zero {
                        context.translateBy(x: rect.midX, y: rect.midY)
                        context.rotate(by: rotation)
                        let path = Path(roundedRect: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height), cornerRadius: rect.width / 2)
                        context.fill(path, with: .color(blue))
                        context.rotate(by: -rotation)
                        context.translateBy(x: -rect.midX, y: -rect.midY)
                    } else {
                        let path = Path(roundedRect: rect, cornerRadius: rect.width / 2)
                        context.fill(path, with: .color(blue))
                    }
                }

                switch kind {
                case .point:
                    fillCapsule(CGRect(x: 25, y: 9 - amount * 5, width: 8, height: 31))
                    context.fill(
                        Path(roundedRect: CGRect(x: 17, y: 34, width: 25, height: 10), cornerRadius: 5),
                        with: .color(blue.opacity(0.42))
                    )

                case .pinch:
                    fillCapsule(CGRect(x: 18 + amount * 4, y: 13 - amount, width: 8, height: 31), rotation: .degrees(34))
                    fillCapsule(CGRect(x: 31 - amount * 4, y: 13 - amount, width: 8, height: 31), rotation: .degrees(-34))

                case .double:
                    // 第一次捏合
                    fillCapsule(CGRect(x: 16, y: 8, width: 6, height: 22), rotation: .degrees(34))
                    fillCapsule(CGRect(x: 25, y: 8, width: 6, height: 22), rotation: .degrees(-34))
                    // 第二次捏合（半透明）
                    let secondAlpha: CGFloat = isActive ? (0.4 + amount * 0.6) : 0.55
                    context.opacity = min(1, secondAlpha)
                    fillCapsule(CGRect(x: 23, y: 16, width: 6, height: 22), rotation: .degrees(34))
                    fillCapsule(CGRect(x: 32, y: 16, width: 6, height: 22), rotation: .degrees(-34))
                    context.opacity = 1

                case .scroll:
                    let dy = amount * 5
                    fillCapsule(CGRect(x: 17, y: 12 + dy, width: 8, height: 31), rotation: .degrees(34))
                    fillCapsule(CGRect(x: 30, y: 12 + dy, width: 8, height: 31), rotation: .degrees(-34))
                    context.fill(
                        Path(roundedRect: CGRect(x: 41, y: 11 + dy, width: 3, height: 34), cornerRadius: 1.5),
                        with: .color(blue.opacity(0.55))
                    )
                }
            }
            .frame(width: 56, height: 56)
        }
        .frame(width: 56, height: 56)
    }
    
    private func ParamGroup() -> some View {
        VStack(spacing: 0) {
            SliderRow(title: AppLanguage.shared.t("settings.cursorSpeed"), value: "\(Int(cursorSpeed * 100))%", progress: $cursorSpeed, configKey: "mouseSensitivity")
            SliderRow(title: AppLanguage.shared.t("settings.pinchSens"), value: "\(Int(pinchSensitivity * 100))%", progress: $pinchSensitivity, configKey: "pinchThreshold")
            SliderRow(title: AppLanguage.shared.t("settings.doubleClick"), value: "\(Int(200 + doubleClickInterval * 300)) ms", progress: $doubleClickInterval, configKey: "")
            SliderRow(title: AppLanguage.shared.t("settings.scrollSpeed"), value: "\(Int(scrollSpeed * 100))%", progress: $scrollSpeed, configKey: "")
            SegmentRow()
        }
        .background(MC.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MC.line, lineWidth: 1)
        }
    }

    private func SettingsGroup() -> some View {
        VStack(spacing: 0) {
            SliderRow(title: AppLanguage.shared.t("settings.cursorSpeed"), value: "\(Int(cursorSpeed * 100))%", progress: $cursorSpeed, configKey: "mouseSensitivity")
            SliderRow(title: AppLanguage.shared.t("settings.pinchSens"), value: "\(Int(pinchSensitivity * 100))%", progress: $pinchSensitivity, configKey: "pinchThreshold")
            SliderRow(title: AppLanguage.shared.t("settings.doubleClick"), value: "\(Int(200 + doubleClickInterval * 300)) ms", progress: $doubleClickInterval, configKey: "")
            SliderRow(title: AppLanguage.shared.t("settings.scrollSpeed"), value: "\(Int(scrollSpeed * 100))%", progress: $scrollSpeed, configKey: "")
            SegmentRow()
            Divider().padding(.leading, 15).opacity(0.64)
            ToggleRow(title: AppLanguage.shared.t("settings.snap"), isOn: $debugSnap)
            ToggleRow(title: AppLanguage.shared.t("settings.clickSound"), isOn: $debugClickSound)
        }
        .background(MC.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MC.line, lineWidth: 1)
        }
    }
    
    private func SliderRow(title: String, value: String, progress: Binding<CGFloat>, configKey: String = "") -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).foregroundStyle(MC.ink)
                Spacer()
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(MC.muted)
                    .monospacedDigit()
            }
            .font(.system(size: 13))
            .frame(height: 32)
            .padding(.horizontal, 15)
            McSlider(progress: progress, configKey: configKey)
                .padding(.horizontal, 15)
                .padding(.bottom, 11)
            Divider().padding(.leading, 15).opacity(0.64)
        }
    }
    
    private func McSlider(progress: Binding<CGFloat>, configKey: String = "") -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let kx = max(7.5, min(w - 7.5, w * progress.wrappedValue))
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.55, green: 0.59, blue: 0.64).opacity(0.25)).frame(height: 4)
                Capsule().fill(Color(red: 0.04, green: 0.52, blue: 1.0)).frame(width: kx, height: 4)
                Circle().fill(.white).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1).offset(x: kx - 7.5)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let newVal = max(0, min(1, v.location.x / w))
                progress.wrappedValue = newVal
                switch configKey {
                case "mouseSensitivity": ConfigManager.shared.currentConfig.mouseSensitivity = Float(newVal * 2.0)
                case "pinchThreshold": ConfigManager.shared.currentConfig.pinchThreshold = Float(40 + newVal * 80)
                default: break
                }
            })
        }.frame(height: 16)
    }
    
    private func SegmentRow() -> some View {
        HStack {
            Text(AppLanguage.shared.t("settings.scrollDir")).foregroundStyle(MC.ink)
            Spacer()
            HStack(spacing: 0) {
                Text(AppLanguage.shared.t("settings.natural")).font(.system(size: 12)).frame(width: 56, height: 24)
                    .background(scrollNatural ? Color.white.opacity(0.90) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .shadow(color: scrollNatural ? Color.black.opacity(0.12) : .clear, radius: 1.5, y: 1)
                    .onTapGesture { scrollNatural = true }
                Text(AppLanguage.shared.t("settings.reversed")).font(.system(size: 12)).frame(width: 56, height: 24)
                    .foregroundStyle(!scrollNatural ? Color(red: 0.17, green: 0.20, blue: 0.24) : Color(red: 0.36, green: 0.40, blue: 0.44))
                    .background(!scrollNatural ? Color.white.opacity(0.90) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .shadow(color: !scrollNatural ? Color.black.opacity(0.12) : .clear, radius: 1.5, y: 1)
                    .onTapGesture { scrollNatural = false }
            }
            .padding(2).background(Color(red: 0.55, green: 0.59, blue: 0.64).opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .font(.system(size: 13))
        .frame(height: 48)
        .padding(.horizontal, 15)
    }
    
    private func DebugGroup() -> some View {
        VStack(spacing: 0) {
            ToggleRow(title: "UI 元素蒙层", isOn: $debugOverlayEnabled)
            ToggleRow(title: AppLanguage.shared.t("settings.snap"), isOn: $debugSnap)
            ToggleRow(title: AppLanguage.shared.t("settings.clickSound"), isOn: $debugClickSound)
        }
        .background(MC.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MC.line, lineWidth: 1)
        }
    }

    private func ExperienceGroup() -> some View {
        VStack(spacing: 0) {
            ToggleRow(title: "UI 元素蒙层", isOn: $debugOverlayEnabled)
            ToggleRow(title: AppLanguage.shared.t("settings.snap"), isOn: $debugSnap)
            ToggleRow(title: AppLanguage.shared.t("settings.clickSound"), isOn: $debugClickSound)
        }
        .background(MC.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MC.line, lineWidth: 1)
        }
    }
    
    private func ToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).foregroundStyle(MC.ink)
                Spacer()
                McSwitch(isOn: isOn.wrappedValue)
                    .onTapGesture {
                        isOn.wrappedValue.toggle()
                        switch title {
                        case "UI 元素蒙层": toggleDebugOverlay(isOn.wrappedValue)
                        case "光标吸附": ConfigManager.shared.currentConfig.assistEnabled = isOn.wrappedValue
                        default: break
                        }
                    }
            }.font(.system(size: 13)).frame(height: 48).padding(.horizontal, 16)
            Divider().opacity(0.7)
        }
    }
    
    private func toggleDebugOverlay(_ enabled: Bool) {
        ConfigManager.shared.currentConfig.debugOverlayEnabled = enabled
        if enabled { debugOverlay.start() }
        else { debugOverlay.stop() }
    }
    
    private func McSwitch(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(isOn ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color(red: 0.55, green: 0.59, blue: 0.64).opacity(0.30))
            .frame(width: 34, height: 21)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 17, height: 17)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1).padding(2)
            }
    }
    
    private func setupPipeline() {
        // 设置 Dock 图标
            if NSApp.applicationIconImage == nil,
               let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                NSApp.applicationIconImage = icon
            }
            EventLogger.startLogFile()
            AppDetector.shared.start()
            cameraService.onSampleBuffer = { [weak detectionPipeline] sampleBuffer in
                detectionPipeline?.didOutputFrame(sampleBuffer)
            }
            // 手势事件 → 动作映射管线
            detectionPipeline.onGesture = { event in
                // 食指弯曲(.indexTap)=左键单击，其他手势按配置映射
#if DEBUG
                print("[DEBUG] onGesture called, type=\(event.gestureType)")
#endif
                guard !event.isRepeat else { return }
                guard MenuBarController.shared.gestureEnabled else { return }  // ← 手势控制开关
                let config = ConfigManager.shared.currentConfig
                guard let action = config.gestureMapping[event.gestureType.rawValue], action.isEnabled else { return }
                switch action.actionType {
                case .mouseMove:
                    let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
                    let x = (event.handPosition.x / 640.0) * screen.width * CGFloat(config.mouseSensitivity)
                    let y = (event.handPosition.y / 480.0) * screen.height * CGFloat(config.mouseSensitivity)
                    mouseCtrl.moveCursor(to: CGPoint(x: x, y: y))
                case .leftClick: mouseCtrl.leftClick(); if debugClickSound { NSSound(named: "Pop")?.play() }
                case .rightClick: mouseCtrl.rightClick()
                case .doubleClick: mouseCtrl.doubleClick(); if debugClickSound { NSSound(named: "Pop")?.play() }
                case .scrollUp: mouseCtrl.scroll(deltaY: Int32(max(1.0, scrollSpeed * 8)) * (scrollNatural ? 1 : -1))
                case .scrollDown: mouseCtrl.scroll(deltaY: -Int32(max(1.0, scrollSpeed * 8)) * (scrollNatural ? 1 : -1))
                case .dragStart: mouseCtrl.mouseDown()
                case .dragEnd: mouseCtrl.mouseUp()
                case .keyPress: keyboardCtrl.pressKey(CGKeyCode(action.actionValue.flatMap { UInt16($0) } ?? 36))
                case .systemCommand:
                    if let cmd = action.actionValue.flatMap({ SystemCommand(rawValue: $0) }) {
                        keyboardCtrl.executeSystemCommand(cmd)
                    }
                default: break
                }
                state.currentGesture = event.gestureType.displayName
                state.gestureConfidence = Float(event.confidence)
                state.handPosition = event.handPosition
                state.handDetected = event.gestureType != .none
                if event.gestureType != .none && !event.isRepeat {
                    commandTriggeredAt = Date()
                }
            }
            // 嘴型回调
            detectionPipeline.onMouthEvent = { event in
                state.mouthStatus = event.status
                state.mouthOpenRatio = event.ratio
            }
            // 注视回调（接收 GazeEstimate）
            detectionPipeline.onGaze = { gazeEstimate in
#if DEBUG
                print("[DEBUG] onGaze called, yaw=\(gazeEstimate.yawOffset)")
#endif
                // 鼠标位置埋点：记录当前系统光标实际位置
#if DEBUG
                print("[MOUSE] location=\(NSEvent.mouseLocation)")
#endif
                state.gazeActive = gazeEstimate.hasFace
                state.gazePosition = CGPoint(x: CGFloat(gazeEstimate.yawOffset),
                                             y: CGFloat(gazeEstimate.pitchOffset))
                guard MenuBarController.shared.cursorEnabled else { return }  // ← 光标控制开关
                cursorController.updateGazeOffset(yaw: gazeEstimate.yawOffset,
                                                  pitch: gazeEstimate.pitchOffset,
                                                  hasFace: gazeEstimate.hasFace)
            }
            // 手部结果回调（关键点 + 方向控制模式）
            detectionPipeline.onHandResult = { handResult, dt in
#if DEBUG
                print("[DEBUG] onHandResult called, hasTip=\(handResult?.indexTip != nil)")
#endif
                guard let handResult = handResult else {
                    handKeypoints = []
                    cursorController.handDisappeared()
                    state.fingerMode = AppLanguage.shared.t("finger.idle")
                    state.currentGesture = AppLanguage.shared.t("finger.idle")
                    state.menuBarText = "空闲"; state.menuBarGreenDot = false
                    MenuBarController.shared.refresh(text: "空闲", isGreen: false)
                    return
                }
                var points: [CGPoint] = []
                if let p = handResult.wrist { points.append(p) }
                if let p = handResult.thumbTip { points.append(p) }
                if let p = handResult.thumbIP { points.append(p) }
                if let p = handResult.thumbMP { points.append(p) }
                if let p = handResult.indexTip { points.append(p) }
                if let p = handResult.indexDIP { points.append(p) }
                if let p = handResult.indexPIP { points.append(p) }
                if let p = handResult.indexMCP { points.append(p) }
                if let p = handResult.middleTip { points.append(p) }
                if let p = handResult.middleDIP { points.append(p) }
                if let p = handResult.middlePIP { points.append(p) }
                if let p = handResult.middleMCP { points.append(p) }
                if let p = handResult.ringTip { points.append(p) }
                if let p = handResult.ringDIP { points.append(p) }
                if let p = handResult.ringPIP { points.append(p) }
                if let p = handResult.ringMCP { points.append(p) }
                if let p = handResult.littleTip { points.append(p) }
                if let p = handResult.littleDIP { points.append(p) }
                if let p = handResult.littlePIP { points.append(p) }
                if let p = handResult.littleMCP { points.append(p) }
                handKeypoints = points

                // 原始数据埋点：每帧关键点质量（暂时关闭避免 String(format:) 异常）
                let kp = handResult
                EventLogger.log(event: "KEYPOINTS", frame: nil, input: "handSide=\(kp.handSide) palmCenter=\(kp.palmCenter?.x ?? 0),\(kp.palmCenter?.y ?? 0)", output: "", duration: nil)

                // 固定原点绝对位置映射（Leap Motion InteractionBox 方案）
                let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
                let config = ConfigManager.shared.currentConfig

                // ⚡ SPIKE: 用 indexMCP 做光标，但只在「单食指伸直」模式激活
                let mode = handResult.fingerMode
                state.fingerMode = mode.displayName
                
                // 更新菜单栏状态
                let pinching = detectionPipeline.isPinching
                if pinching && !detectionPipeline.cursorFrozen {
                    state.menuBarText = "滚动"; state.menuBarGreenDot = true
                } else if pinching {
                    state.menuBarText = "点击"; state.menuBarGreenDot = true
                } else if mode == .cursor {
                    state.menuBarText = "移动"; state.menuBarGreenDot = true
                } else if handResult.confidence > 0.15 {
                    state.menuBarText = "就绪"; state.menuBarGreenDot = true
                } else {
                    state.menuBarText = "空闲"; state.menuBarGreenDot = false
                }
                MenuBarController.shared.refresh(text: state.menuBarText, isGreen: state.menuBarGreenDot)
                
                if let center = handResult.indexMCP, handResult.confidence > 0.15, mode == .cursor,
                   !detectionPipeline.cursorFrozen, MenuBarController.shared.cursorEnabled {
                    // 混合指尖偏移：手指弯向某方向→光标跟过去
                    let tipGain: CGFloat = 1.0
                    var adjusted = center
                    if let tip = handResult.indexTip {
                        adjusted.x += (tip.x - center.x) * tipGain
                        adjusted.y += (tip.y - center.y) * tipGain
                    }
                    lostFrameCount = 0
                    if !cursorController.fingerActive {
                        cursorController.handAppeared()
                    }
                    cursorController.updateWithAbsolutePosition(
                        handCenter: adjusted,
                        screenSize: screen,
                        gain: config.mouseSensitivity,
                        handedness: handResult.handSide
                    )
                    let finalCursor = cursorController.computeCursor(screenSize: screen, sensitivity: 1.0, dt: CGFloat(dt))
                    mouseCtrl.moveCursor(to: finalCursor)
                } else {
                    lostFrameCount += 1
                    if lostFrameCount > 15 {
                        cursorController.handDisappeared()
                        lostFrameCount = 0
                    }
                }
            }
            // 人脸结果回调（关键点）
            detectionPipeline.onFaceResult = { faceResult in
                guard let faceResult = faceResult else { faceKeypoints = []; return }
                var points: [CGPoint] = []
                if let contour = faceResult.faceContour { points.append(contentsOf: contour) }
                if let leftEye = faceResult.leftEye { points.append(contentsOf: leftEye) }
                if let rightEye = faceResult.rightEye { points.append(contentsOf: rightEye) }
                if let leftPupil = faceResult.leftPupil { points.append(leftPupil) }
                if let rightPupil = faceResult.rightPupil { points.append(rightPupil) }
                if let outerLips = faceResult.outerLipsAbsolute { points.append(contentsOf: outerLips) }
                if let innerLips = faceResult.innerLipsAbsolute { points.append(contentsOf: innerLips) }
                faceKeypoints = points
            }
            cameraService.onFPSUpdate = { fps, count in
                state.currentFPS = fps
                state.frameCount = count
            }
            detectionPipeline.start()
            detectionPipeline.startGazeCalibration()
            
            // 60fps 补帧定时器：Lerp 追赶检测帧设定的 targetPosition
            // 每帧只移动一小步（lerp=0.35），即使目标很远也不会跳变
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0/120.0, repeats: true) { _ in
                guard cursorController.fingerActive else { return }
                guard MenuBarController.shared.cursorEnabled else { return }  // ← 光标控制开关
                let lerp: CGFloat = 0.65  // 更快追赶目标，减少滞后感
                let pos = cursorController.currentPosition
                let target = cursorController.targetPosition
                let newX = pos.x + (target.x - pos.x) * lerp
                let newY = pos.y + (target.y - pos.y) * lerp
                cursorController.currentPosition = CGPoint(x: newX, y: newY)
                mouseCtrl.moveCursor(to: CGPoint(x: newX, y: newY))
            }
            // 保证补帧定时器不被 UI 事件阻塞
            RunLoop.current.add(timer, forMode: .common)
            self.frameGenTimer = timer
            
            CameraService.shared = cameraService
            let configuredDeviceID = ConfigManager.shared.currentConfig.cameraDeviceID
            // 请求权限后启动摄像头（延迟等窗口完全进入前台）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        state.cameraGranted = granted
                        cameraService.start(withDeviceID: configuredDeviceID.isEmpty ? nil : configuredDeviceID)
                    }
                }
            }
            // 注册 AXHelper LaunchAgent（首次需用户授权）
            registerAXHelper()
            // 初始化：关闭调试蒙层
            ConfigManager.shared.currentConfig.debugOverlayEnabled = false
            debugOverlay.stop()
            uiScanner.start()
            cursorController.uiScanner = uiScanner
            // 调试蒙层定时器：只在 overlay 开启后工作
            let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                guard ConfigManager.shared.currentConfig.debugOverlayEnabled else { return }
                let cursor = NSEvent.mouseLocation  // Cocoa（y=0 底）
                let screenH = NSScreen.main?.frame.height ?? 1080
                var nearestQC: CGPoint? = nil
                if let near = uiScanner.nearElement {
                    nearestQC = CGPoint(x: near.frame.midX, y: near.frame.midY)  // Quartz
                }
                // 没命中时 fallback：找所有元素中圆心最近的
                if nearestQC == nil {
                    var bestDist = CGFloat.greatestFiniteMagnitude
                    for el in uiScanner.cachedElements {
                        let dx = el.frame.midX - cursor.x
                        let dy = (screenH - el.frame.midY) - cursor.y  // 翻到 Cocoa 算距离
                        let d = sqrt(dx*dx + dy*dy)
                        if d < bestDist { bestDist = d; nearestQC = CGPoint(x: el.frame.midX, y: el.frame.midY) }
                    }
                }
                // nearestCenter 从 AX 的 Quartz 翻到 Cocoa
                var nearestCocoa: CGPoint? = nil
                if let nc = nearestQC {
                    nearestCocoa = CGPoint(x: nc.x, y: screenH - nc.y)
                }
                debugOverlay.update(elements: uiScanner.cachedElements, cursor: cursor, nearestCenter: nearestCocoa)
            }
            RunLoop.current.add(t, forMode: .common)
            self.overlayTimer = t
        }
    
    private func teardownPipeline() {
        cameraService.stop()
        cameraService.onSampleBuffer = nil
        uiScanner.stop()
        frameGenTimer?.invalidate()
        frameGenTimer = nil
        overlayTimer?.invalidate()
        overlayTimer = nil
        debugOverlay.stop()
        EventLogger.stopLogFile()
    }
    
    /// 启动 AXHelper：优先 LaunchAgent，签名失败则委托 uiScanner spawn
    private func registerAXHelper() {
        // 1. 尝试 LaunchAgent 注册
        do {
            let agent = SMAppService.agent(plistName: "com.motioncontrol.axhelper")
            try agent.register()
            EventLogger.log(event: "axHelper", frame: nil, input: "launchAgent registered", output: "status=\(agent.status.rawValue)", duration: 0)
            return
        } catch {
            EventLogger.log(event: "axHelper", frame: nil, input: "register failed, fallback to spawn", output: error.localizedDescription, duration: 0)
        }
        // 2. 委托 UIElementScanner spawn AXHelper
        uiScanner.spawnAXHelper()
    }
}
