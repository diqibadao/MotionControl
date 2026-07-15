import SwiftUI

struct DetectionParamsView: View {
    @ObservedObject var configManager = ConfigManager.shared

    @State private var gestureSensitivity: Double = 0.5
    @State private var mouseSpeed: Double = 0.5
    @State private var availableCameras: [CameraInfo] = CameraService.availableCameras()
    @State private var selectedCameraID: String = ""

    private var gazeEnabledBinding: Binding<Bool> {
        Binding(
            get: { configManager.currentConfig.gazeEnabled },
            set: { configManager.currentConfig.gazeEnabled = $0 }
        )
    }

    private var gazeSensitivityBinding: Binding<Double> {
        Binding(
            get: { Double(configManager.currentConfig.gazeSensitivity) },
            set: { configManager.currentConfig.gazeSensitivity = Float($0) }
        )
    }

    var body: some View {
        Form {
            Section("手势灵敏度") {
                Slider(value: $gestureSensitivity, in: 0...1, step: 0.05)
                Text("值: \(gestureSensitivity, specifier: "%.2f")")
            }

            Section("鼠标速度") {
                Slider(value: $mouseSpeed, in: 0...1, step: 0.05)
                Text("值: \(mouseSpeed, specifier: "%.2f")")
            }

            Section("注视跟随") {
                Toggle("启用注视跟随", isOn: gazeEnabledBinding)
            }

            Section("注视灵敏度") {
                Slider(value: gazeSensitivityBinding, in: 0...1, step: 0.05)
                Text("值: \(gazeSensitivityBinding.wrappedValue, specifier: "%.2f")")
            }

            Section("摄像头") {
                Picker("选择摄像头", selection: $selectedCameraID) {
                    ForEach(availableCameras) { camera in
                        Text(camera.name).tag(camera.id)
                    }
                }
                .onChange(of: selectedCameraID) { _, newID in
                    configManager.currentConfig.cameraDeviceID = newID
                    try? configManager.save()
                    CameraService.shared?.switchCamera(to: newID)
                }
            }
        }
        .padding()
        .onAppear {
            selectedCameraID = configManager.currentConfig.cameraDeviceID
        }
    }
}
