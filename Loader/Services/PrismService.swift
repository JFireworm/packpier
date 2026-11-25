import CoreFoundation
import Foundation

/// Serializes edits per library instance, preserving unrecognized fields in existing preferences.
actor PrismService {
    private static let palette = ["#62A1FF", "#8C87FF", "#B47BFA", "#EF79E5", "#FF79A9", "#FF746F", "#FFA153", "#FFD059",
                                  "#E0EE69", "#A7E85D", "#69DA83", "#4FDCB4", "#44DDD9", "#56D4FA", "#F2B68B", "#A9C1E1"]
    private let root: URL
    private let directory: URL
    private var lastLanguage: String?

    init(codexRoot: URL, dataDirectory: URL) {
        root = codexRoot
        directory = dataDirectory
    }

    private func preferencesURL(_ catalog: PrismCatalog) -> URL {
        directory.appendingPathComponent("preferences-" + catalog.account + ".json")
    }

    private func preferences(_ catalog: PrismCatalog) throws -> JSONObject {
        do {
            var prefs = try readJSONObject(preferencesURL(catalog))
            guard let version = prefs["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
                  version.doubleValue == 1 else { throw WireError.message("不支持的偏好版本") }
            prefs["threadColorModes"] = prefs["threadColorModes"] ?? [:]
            prefs["recentColors"] = prefs["recentColors"] ?? []
            return prefs
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return ["version": 1, "mode": "all", "colors": [:], "threadColorModes": [:], "recentColors": [],
                    "inheritance": [:], "groups": [], "assignments": [:], "order": []]
        }
    }

    static func language(_ preference: String?, preferred: [String]) -> String {
        if let preference, !preference.isEmpty && preference != "auto" {
            return ["en", "ja", "ko", "zh-CN", "zh-TW"].contains(preference) ? preference : "en"
        }
        for tag in preferred {
            let parts = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .replacingOccurrences(of: "_", with: "-").split(separator: "-")
            guard let first = parts.first else { continue }
            if first == "zh" {
                for part in parts.dropFirst() {
                    if ["hant", "tw", "hk", "mo"].contains(part) { return "zh-TW" }
                    if part == "hans" { break }
                }
                return "zh-CN"
            }
            if ["en", "ko", "ja"].contains(first) { return String(first) }
        }
        return "en"
    }

    private func language() -> String {
        let url = directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("app-state.json")
        var preference: String?
        do { preference = try readJSONObject(url)["language"] as? String }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile {}
        catch { if let lastLanguage { return lastLanguage } }
        let value = Self.language(preference, preferred: Locale.preferredLanguages)
        lastLanguage = value
        return value
    }

    func snapshot() throws -> JSONObject {
        try sidebar(account: nil, operation: nil)
    }

    func update(account: String, operation: JSONObject) throws -> JSONObject {
        try sidebar(account: account, operation: operation)
    }

    private func sidebar(account: String?, operation: JSONObject?) throws -> JSONObject {
        let catalog = try PrismCatalog(root: root)
        if let account, account != catalog.account { throw WireError.message("Codex 账户已切换，请重新选择") }
        var prefs = try preferences(catalog)
        let modes = prefs["threadColorModes"] as? [String: String] ?? [:]
        let colors = prefs["colors"] as? JSONObject ?? [:]
        var inherited = Set(modes.keys.filter { modes[$0] == "project" && colors[$0] == nil })
        let editKey = operation?["type"] as? String == "color" ? operation?["key"] as? String : nil
        if let editKey, operation?["source"] as? String == "project" { inherited.insert(editKey) }
        var (state, editable) = try catalog.sidebar(inherited: inherited, editing: editKey)
        if let operation {
            try Self.apply(operation, to: &prefs, editable: editable)
            try writeJSONObject(prefs, to: preferencesURL(catalog))
        }
        prefs["mode"] = prefs["mode"] as? String == "project" ? "project" : "all"
        state["preferences"] = prefs
        state["language"] = language()
        return state
    }

    private static func apply(_ op: JSONObject, to prefs: inout JSONObject, editable: Set<String>) throws {
        let type = op["type"] as? String
        if type == "mode", let mode = op["value"] as? String, ["all", "project"].contains(mode) {
            prefs["mode"] = mode
            return
        }
        guard type == "color" || type == "preset-color" else { throw WireError.message("无效的侧栏设置") }
        let color = (op["value"] as? String)?.uppercased()
        guard op["value"] is NSNull || color?.range(of: #"\A#[0-9A-F]{6}\z"#, options: .regularExpression) != nil else {
            throw WireError.message("请输入六位十六进制颜色")
        }
        if type == "preset-color" {
            var palette = prefs["presetColors"] as? [String] ?? Self.palette
            guard let color, let slot = op["slot"] as? NSNumber, CFGetTypeID(slot) != CFBooleanGetTypeID(),
                  let index = Int(exactly: slot.doubleValue), Self.palette.indices.contains(index),
                  palette.indices.contains(index) else { throw WireError.message("无效的预设色格") }
            palette[index] = color
            prefs["presetColors"] = palette
            return
        }
        guard let key = op["key"] as? String else { throw WireError.message("无效的侧栏设置") }
        let isProject = key.hasPrefix("project:")
        guard editable.contains(key) else {
            throw WireError.message(isProject ? "条目已移出排行榜，请刷新" : "会话不在当前排行榜")
        }
        if key.hasPrefix(PrismCatalog.threadPrefix + PrismCatalog.clientThreadPrefix) {
            throw WireError.message("会话尚未同步完成")
        }
        let source = op["source"] as? String
        if op["source"] != nil, isProject || color != nil || !["default", "project"].contains(source ?? "") {
            throw WireError.message("无效的颜色来源")
        }
        guard var colors = prefs["colors"] as? JSONObject else { throw WireError.message("无效的配色格式") }
        colors[key] = color
        prefs["colors"] = colors
        if isProject {
            if let inherit = op["inherit"] as? NSNumber, CFGetTypeID(inherit) == CFBooleanGetTypeID() {
                var inheritance = prefs["inheritance"] as? JSONObject ?? [:]
                inheritance[String(key.dropFirst(8))] = inherit.boolValue
                prefs["inheritance"] = inheritance
            }
        } else {
            var modes = prefs["threadColorModes"] as? JSONObject ?? [:]
            modes[key] = source
            prefs["threadColorModes"] = modes
        }
        if let color {
            let recent = prefs["recentColors"] as? [String] ?? []
            prefs["recentColors"] = Array(([color] + recent.filter { $0 != color }).prefix(6))
        }
    }
}
