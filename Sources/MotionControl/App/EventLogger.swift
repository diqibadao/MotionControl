import Foundation

class EventLogger {
    /// 当前日志文件路径（供分析脚本读取）
    static private(set) var currentLogPath: String?

    private static let logQueue = DispatchQueue(label: "com.motioncontrol.eventlogger", qos: .utility)
    private static var logFileURL: URL?
    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// 启动日志文件（APP 启动时调用一次）
    static func startLogFile() {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let name = "run_\(df.string(from: Date())).log"
        // 使用绝对路径，避免 open 启动时 CWD 变为 / 导致日志写入失败
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirURL = home.appendingPathComponent("Desktop/vibe项目/MotionControl/Data/logs/raw")
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let fileURL = dirURL.appendingPathComponent(name)
        // 创建文件（空文件）
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        logFileURL = fileURL
        currentLogPath = fileURL.path
        print("[EVENTLOGGER] 日志文件: \(fileURL.path)")
    }

    /// 停止日志（APP 退出时调用）
    static func stopLogFile() {
        logQueue.sync {}
    }

    /// 输出日志到 stdout + 文件
    static func log(event: String, frame: Int?, input: String, output: String, duration: Double?) {
        let timestamp = df.string(from: Date())
        var line = "[\(timestamp)]"
        line += " [\(event)]"
        if let f = frame {
            line += " [frame:\(f)]"
        }
        line += " IN: \(input) → OUT: \(output)"
        if let d = duration {
            let ms = Int(d * 1000)
            line += " (\(ms)ms)"
        }
        print(line)

        guard let url = logFileURL else { return }
        let lineWithNewline = line + "\n"
        logQueue.async {
            if let data = lineWithNewline.data(using: .utf8) {
                if let fh = try? FileHandle(forUpdating: url) {
                    fh.seekToEndOfFile()
                    try? fh.write(contentsOf: data)
                    try? fh.close()
                }
            }
        }
    }
}
