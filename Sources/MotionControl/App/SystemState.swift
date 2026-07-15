import Foundation
import SwiftUI

@Observable
final class SystemState {
    // 摄像头
    var cameraState: String = "stopped"
    var currentFPS: Double = 0
    var frameCount: Int = 0
    
    // 检测状态
    var handDetected: Bool = false
    var faceDetected: Bool = false
    var currentGesture: String = "—"
    var gestureConfidence: Float = 0
    var handPosition: CGPoint = .zero
    var gazeActive: Bool = false
    var gazePosition: CGPoint = .zero
    var mouthOpenRatio: Float = 0
    var mouthStatus: MouthStatus = .closed
    
    var fingerMode: String = "IDLE"
    var menuBarText: String = "空闲"
    var menuBarGreenDot: Bool = false
    
    // 语音
    var voiceState: String = "idle"
    var voiceText: String = ""
    var voicePartialText: String = ""
    
    // 权限
    var cameraGranted: Bool = false
    var micGranted: Bool = false
    var speechGranted: Bool = false
    var accessibilityGranted: Bool = false
    
    // 配置
    var configChanged: Bool = false
}
