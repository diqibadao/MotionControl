import Foundation

class EventLogger {
    /// 输出日志，格式：[日期] [事件] [frame:?] IN:输入 → OUT:输出 (耗时ms)
    static func log(event: String, frame: Int?, input: String, output: String, duration: Double?) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = df.string(from: Date())
        var log = "[\(timestamp)]"
        log += " [\(event)]"
        if let f = frame {
            log += " [frame:\(f)]"
        }
        log += " IN: \(input) → OUT: \(output)"
        if let d = duration {
            let ms = Int(d * 1000) // 假设 duration 以秒为单位，转换为毫秒
            log += " (\(ms)ms)"
        }
        print(log)
    }
}
