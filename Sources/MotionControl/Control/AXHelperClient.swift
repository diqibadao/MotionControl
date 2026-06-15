// Sources/MotionControl/Control/AXHelperClient.swift
// XPC 客户端：连接 AXHelper LaunchAgent，请求 AX 扫描
import Foundation

// 与 AXHelper 的协议保持一致
@objc private protocol AXHelperProtocol {
    func scan(reply: @escaping (Data) -> Void)
}

private struct ElementDTO: Codable {
    let role: String; let frame: [Double]; let title: String
    let pid: Int; let windowBounds: [Double]
}

class AXHelperClient {
    static let shared = AXHelperClient()

    private var connection: NSXPCConnection?
    private let serviceName = "com.motioncontrol.axhelper"

    func connect() {
        connection?.invalidate()
        let conn = NSXPCConnection(serviceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: AXHelperProtocol.self)
        conn.resume()
        connection = conn
    }

    func scan(completion: @escaping ([UIElementInfo]) -> Void) {
        guard let conn = connection,
              let proxy = conn.remoteObjectProxy as? AXHelperProtocol else {
            completion([])
            return
        }

        proxy.scan { data in
            guard let list = try? JSONDecoder().decode([ElementDTO].self, from: data) else {
                completion([])
                return
            }
            let elements = list.compactMap { el -> UIElementInfo? in
                guard el.frame.count == 4, el.windowBounds.count == 4 else { return nil }
                return UIElementInfo(
                    role: el.role, title: el.title,
                    frame: CGRect(x: el.frame[0], y: el.frame[1], width: el.frame[2], height: el.frame[3]),
                    isEnabled: true, subrole: nil, owningPID: el.pid,
                    windowBounds: CGRect(x: el.windowBounds[0], y: el.windowBounds[1], width: el.windowBounds[2], height: el.windowBounds[3])
                )
            }
            completion(elements)
        }
    }
}
