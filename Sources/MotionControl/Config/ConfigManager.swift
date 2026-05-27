import Foundation
import Combine

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var currentConfig: GestureConfig
    @Published var activeProfile: String = "日常使用"
    @Published var availableProfiles: [String] = ["日常使用"]
    
    private let fileManager = FileManager.default
    private var configDirectory: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("com.motioncontrol")
        return dir
    }
    private var configFile: URL {
        configDirectory.appendingPathComponent("config.json")
    }
    private var source: DispatchSourceFileSystemObject?
    private let configQueue = DispatchQueue(label: "com.motioncontrol.config")
    
    private init() {
        currentConfig = GestureConfig.default
        load()
        startWatching()
    }
    
    func load() {
        do {
            if fileManager.fileExists(atPath: configFile.path) {
                let data = try Data(contentsOf: configFile)
                let decoder = JSONDecoder()
                currentConfig = try decoder.decode(GestureConfig.self, from: data)
                activeProfile = currentConfig.activeProfile
            } else {
                // 首次启动写入默认配置
                try save(currentConfig)
            }
        } catch {
            print("[Config] 加载配置失败：\(error.localizedDescription)，使用默认配置")
            currentConfig = GestureConfig.default
        }
    }
    
    func save(_ config: GestureConfig? = nil) throws {
        let configToSave = config ?? currentConfig
        if !fileManager.fileExists(atPath: configDirectory.path) {
            try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }
        // 原子写入：先写临时文件再 rename
        let tempFile = configFile.appendingPathExtension("tmp")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configToSave)
        try data.write(to: tempFile)
        _ = try fileManager.replaceItemAt(configFile, withItemAt: tempFile)
        print("[Config] 配置已保存到 \(configFile.path)")
    }
    
    func switchProfile(_ name: String) {
        // 简单方案：保存当前配置，加载新配置（扩展为多方案时实现）
        activeProfile = name
        currentConfig.activeProfile = name
        try? save()
        print("[Config] 切换到配置方案：\(name)")
    }
    
    func addMapping(_ action: GestureAction) {
        currentConfig.gestureMapping[action.gesture.rawValue] = action
        try? save()
    }
    
    func removeMapping(for gesture: GestureType) {
        currentConfig.gestureMapping.removeValue(forKey: gesture.rawValue)
        try? save()
    }
    
    func resetToDefaults() {
        currentConfig = GestureConfig.default
        try? save()
        print("[Config] 已恢复默认配置")
    }
    
    // MARK: - 热加载
    private func startWatching() {
        guard fileManager.fileExists(atPath: configFile.path) else { return }
        let fd = open(configFile.path, O_EVTONLY)
        guard fd >= 0 else { return }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: configQueue)
        source?.setEventHandler { [weak self] in
            self?.load()
            print("[Config] 配置文件已变更，已热加载")
        }
        source?.setCancelHandler { close(fd) }
        source?.resume()
    }
    
    deinit {
        source?.cancel()
    }
}
