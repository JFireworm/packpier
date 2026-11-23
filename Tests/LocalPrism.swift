import AppKit
import Foundation

@main struct LocalPrism {
    @MainActor static func wait(_ m: Manager, _ label:String, seconds:Int = 45, until test: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(Double(seconds))
        while !test() {
            if let error = m.error ?? m.state.failure("prism") { throw PackpierError.message(label + " · " + error) }
            if Date() >= deadline { throw PackpierError.message(label + " 超时 · " + m.connection + " · " + String(describing:m.state.packages.map { ($0.id,$0.version,$0.fields["buildDisposition"],$0.canAuthorize,$0.node.keys.sorted()) })) }
            try await Task.sleep(nanoseconds:100_000_000)
        }
    }
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in await runSuite() }
        app.run()
        exit(2)
    }
    @MainActor static func runSuite() async {
        let m = Manager(), fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("packpier-isolated-" + UUID().uuidString)
        var failed = false
        do {
            try MarketApplicationsCheck.run()
            let appPath = ProcessInfo.processInfo.environment["PACKPIER_TEST_APP"] ?? "build/Packpier.app"
            guard let bundle = Bundle(path:appPath) else { throw PackpierError.message("Build Packpier before testing") }
            let host = try HostLocation.bundled(in:bundle)
            let store = temp.appendingPathComponent("Codex Tweaks/State")
            try fm.createDirectory(at:store,withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:["schemaVersion":1,"enabled":false,"knownPackageIDs":[],"disabledPackageIDs":[],"updateAutoCheck":false]).write(to:store.appendingPathComponent("app-state.json"))
            var params = host.parameters(support:temp,cache:temp.appendingPathComponent("cache"))
            params["bundledPackagesDirectory"] = ""
            let policy = "(version 1)(allow default)(deny network-outbound)(deny process-exec (literal \"/usr/bin/open\"))"
            var env = ProcessInfo.processInfo.environment
            env["npm_config_offline"] = "true"
            try m.startSession(executable:URL(fileURLWithPath:"/usr/bin/sandbox-exec"),arguments:["-p",policy,host.executable.path],params:params,environment:env)
            try await wait(m,"初始化") { m.state.ready }
            guard !m.state.enabled, m.state.packages.isEmpty else { throw PackpierError.message("隔离基线异常") }
            let source = URL(fileURLWithPath:CommandLine.arguments[1])
            m.readFile(source)
            try await wait(m,"预览 ZIP"){ m.preview != nil }
            guard let preview = m.preview, preview.name == "prism", preview.reason != nil else { throw PackpierError.message("权限预览缺失") }
            let version = preview.version
            m.confirmImport()
            try await wait(m,"导入、启用、编译",seconds:70){
                m.state.packages.contains { $0.id == "prism" && $0.hasBuild && $0.builtCurrent && m.state.hasEnabled($0.id) }
            }
            let p = m.state.packages.first { $0.id == "prism" }!
            guard p.version == version, p.node["authorized"] as? Bool == false, p.canAuthorize else { throw PackpierError.message("受控 Node 授权状态异常 " + String(describing:p.node.keys.sorted()) + String(describing:p.actions.keys.sorted())) }
            m.requestTrust(p)
            guard m.authorization?.version == version else { throw PackpierError.message("无法显示当前构建的授权") }
            m.authorization = nil
            m.readFile(source)
            try await wait(m,"再次选择 ZIP") { m.preview != nil }
            m.confirmImport()
            guard m.state.packages.count == 1 else { throw PackpierError.message("重复安装") }
            m.send("setPackageEnabled",["packageID":p.id,"enabled":false])
            try await wait(m,"停用",seconds:5){ !m.state.hasEnabled(p.id) }
            m.activate(p)
            try await wait(m,"启用"){ m.state.hasEnabled(p.id) }
            try await PackageOrderCheck.run(m,support:temp,params:params,arguments:["-p",policy,host.executable.path],environment:env)
            print("PASS zip preview → import → enable → official build → explicit authorization sheet; duplicate reuse and disable/enable; \(p.id) \(version)")
        } catch { print("FAIL " + error.localizedDescription); failed = true }
        await withCheckedContinuation { continuation in m.finish { continuation.resume() } }
        do { try fm.removeItem(at:temp) } catch { print(error.localizedDescription); failed = true }
        exit(failed ? 1 : 0)
    }
}
