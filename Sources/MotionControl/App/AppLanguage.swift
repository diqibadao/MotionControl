import Foundation

/// 中英文切换管理器，基于 JSON 配置
final class AppLanguage {
    static let shared = AppLanguage()
    
    private let key = "AppLanguage.isChinese"
    private var dict: [String: [String: String]] = [:]
    
    var isChinese: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            onToggle?()
        }
    }
    
    var onToggle: (() -> Void)?
    
    private init() {
        loadJSON()
    }
    
    /// 取本地化文本
    func t(_ key: String) -> String {
        let lang = isChinese ? "zh" : "en"
        return dict[key]?[lang] ?? key
    }
    
    private func loadJSON() {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]]
        else { return }
        dict = json
    }
}
