import Foundation

struct HostLocation {
    let resources: URL
    let executable: URL
    static func bundled(in bundle: Bundle = .main) throws -> Self {
        let executable = bundle.bundleURL.appendingPathComponent("Contents/Helpers/packpier-codex-loader")
        guard let resources = bundle.resourceURL, FileManager.default.isExecutableFile(atPath:executable.path) else {
            throw PackpierError.message("Packpier 缺少内置 Codex 加载器。")
        }
        return Self(resources:resources, executable:executable)
    }
    func parameters(support: URL, cache: URL) -> Fields {
        ["applicationSupportDirectory": support.path, "cacheDirectory": cache.path,
         "bundledPackagesDirectory": resources.appendingPathComponent("BundledPlugins").path,
         "skillPath": resources.appendingPathComponent("Skills/packpier-plugin-author/SKILL.md").path,
         "currentVersion": "3.5.12",
         "buildNumber": "55",
         "preferredLanguages": Locale.preferredLanguages]
    }
}

// Each instance owns one child and its private pipes. Messages are delivered in wire order.
final class Loader {
    let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var sequence = 0
    private var closing = false
    private let receive: (Fields) -> Void
    private let ended: () -> Void
    init(receive: @escaping (Fields) -> Void, ended: @escaping () -> Void) {
        self.receive = receive
        self.ended = ended
    }
    func start(executable: URL, arguments: [String] = [], environment: [String:String]? = nil) throws {
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let handle = output.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var buffer = Data()
            while true {
                let part = handle.availableData
                if part.isEmpty { break }
                buffer.append(part)
                while let index = buffer.firstIndex(of: 10) {
                    let line = buffer[..<index]
                    if let decoded = try? JSONSerialization.jsonObject(with: line) as? Fields {
                        DispatchQueue.main.async { self.receive(decoded) }
                    }
                    buffer.removeSubrange(...index)
                }
            }
            process.waitUntilExit()
            DispatchQueue.main.async { self.ended() }
        }
    }
    @discardableResult
    func request(_ method: String, _ params: Fields = [:]) throws -> Int {
        if method == "deletePackage", let id = params["packageID"] as? String, BuiltInPackages.ids.contains(id) {
            throw PackpierError.message("内置插件不能删除。")
        }
        guard !closing && process.isRunning else { throw PackpierError.message("加载器尚未连接。") }
        sequence += 1
        var bytes = try JSONSerialization.data(withJSONObject: ["id":sequence, "method":method, "params":params])
        bytes.append(10)
        try input.fileHandleForWriting.write(contentsOf: bytes)
        return sequence
    }
    func close() {
        guard !closing else { return }
        closing = true
        // EOF invokes the official controller's graceful shutdown, even during initialization.
        try? input.fileHandleForWriting.close()
    }
}

struct TweakPackage: Identifiable {
    let fields: Fields
    var id: String { fields["id"] as? String ?? "" }
    var title: String {
        switch id {
        case "prism": return "Prism"
        case "p-sign": return "P-Sign"
        default: return fields["displayName"] as? String ?? id
        }
    }
    var version: String { fields["displayVersion"] as? String ?? manifest["version"] as? String ?? "—" }
    var manifest: Fields { fields["manifest"] as? Fields ?? [:] }
    var detail: String { manifest["description"] as? String ?? "" }
    var node: Fields { fields["node"] as? Fields ?? [:] }
    var actions: Fields { fields["availableActions"] as? Fields ?? [:] }
    var presentation: Fields { fields["presentation"] as? Fields ?? [:] }
    var directory: String { fields["directory"] as? String ?? "" }
    var priority: Int { fields["priority"] as? Int ?? 0 }
    var hasBuild: Bool { fields["activeBuild"] is Fields }
    var builtCurrent: Bool { fields["buildDisposition"] as? String == "current" }
    var canBuild: Bool { actions["build"] as? Bool ?? (fields["validationError"] as? String == nil) }
    var canAuthorize: Bool { actions["authorizeNode"] as? Bool == true && !(node["authorizationID"] as? String ?? "").isEmpty }
}

struct HostState {
    var raw: Fields = [:]
    var ready: Bool { raw["packages"] != nil }
    var enabled: Bool { raw["enabled"] as? Bool == true }
    var status: String { (raw["status"] as? Fields)?["kind"] as? String ?? "" }
    var connected: Bool { status == "connected" }
    var packages: [TweakPackage] { (raw["packages"] as? [Fields] ?? []).map(TweakPackage.init) }
    func hasEnabled(_ id: String) -> Bool { !(raw["disabledPackageIDs"] as? [String] ?? []).contains(id) }
    func building(_ id: String) -> Bool { (raw["buildingPackageIDs"] as? [String] ?? []).contains(id) }
    func failure(_ id: String) -> String? {
        for key in ["packageBuildErrors","packagePayloadErrors","packageRuntimeErrors"] {
            if let message = (raw[key] as? [String:String])?[id], !message.isEmpty { return message }
        }
        return nil
    }
    func label(_ p: TweakPackage) -> String {
        if !hasEnabled(p.id) { return "已停用" }
        if building(p.id) { return "正在编译" }
        if failure(p.id) != nil || p.fields["validationError"] is String { return "需要处理" }
        if !p.hasBuild { return "待编译" }
        if p.canAuthorize { return "待授权" }
        if !enabled { return "加载器已暂停" }
        if !connected { return "等待连接" }
        if p.node["running"] as? Bool == true { return "已运行" }
        return p.presentation["statusTitle"] as? String ?? "已编译"
    }
}
