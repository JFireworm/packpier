import Foundation

enum PackageOrderCheck {
    @MainActor static func run(_ m: Manager, support: URL, params: Fields, arguments:[String], environment:[String:String]) async throws {
        let fm = FileManager.default
        let packages = support.appendingPathComponent("Codex Tweaks/Tweaks/packages")
        for id in ["ct-a","ct-b","ct-c"] {
            let dir = packages.appendingPathComponent(id)
            try fm.createDirectory(at:dir,withIntermediateDirectories:true)
            let dependencies: Fields = id == "ct-c" ? ["ct-a":["version":"*"]] : [:]
            let manifest: Fields = ["name":id,"version":"1.0.0","type":"module",
                "codexTweaks":["apiVersion":3,"priority":0,"entrypoints":["renderer":"index.js"],"packageDependencies":dependencies] as Fields]
            try JSONSerialization.data(withJSONObject:manifest).write(to:dir.appendingPathComponent("package.json"))
            try Data("export function setup() {}".utf8).write(to:dir.appendingPathComponent("index.js"))
        }
        m.send("reloadPackages")
        try await LocalPrism.wait(m,"发现排序测试包"){ m.state.packages.count == 4 }
        m.authorization = nil
        try NativeUI.checkTime()
        try WeChatOverlayCheck.run()
        try await NativeUI.checkDrag(m)
        func ids() -> [String] { m.state.packages.map(\.id) }
        func require(_ ok: Bool, _ detail: String) throws {
            if !ok { throw PackpierError.message(detail + " · " + (m.error ?? ids().joined(separator:", "))) }
        }
        // A drop onto a visible neighbour while other rows are hidden still uses the complete host list.
        let noticeBeforeMove = m.notice
        await m.movePackage("prism",to:"ct-c",after:false)
        try require(m.notice == noticeBeforeMove, "成功排序不应新增提示")
        try require(ids() == ["ct-a","ct-b","prism","ct-c"], "相同顺序值的插入失败")
        await m.movePackage("prism",to:"ct-a",after:false)
        try require(ids() == ["prism","ct-a","ct-b","ct-c"],"移至首行失败")
        await m.movePackage("ct-b",to:"ct-c",after:true)
        let expected = ["prism","ct-a","ct-c","ct-b"]
        try require(ids() == expected,"移至末行失败")
        await m.movePackage("ct-c",to:"ct-a",after:false)
        try require(m.error?.contains("依赖") == true && ids() == expected,"依赖冲突处理失败")
        m.error = nil
        m.send("setUpdateChannel",["channel":"beta"])
        try await LocalPrism.wait(m,"更新通道"){ (m.state.raw["update"] as? Fields)?["channel"] as? String == "beta" }
        m.send("setLanguage",["language":"en"])
        try await LocalPrism.wait(m,"加载器语言"){ (m.state.raw["presentation"] as? Fields)?["languagePreference"] as? String == "en" }
        m.send("refreshLog")
        try await LocalPrism.wait(m,"刷新日志"){ !(m.state.raw["logText"] as? String ?? "").isEmpty }
        try require(m.logURL.path.hasPrefix(support.path), "日志应在隔离目录")
        m.send("clearLog")
        try await LocalPrism.wait(m,"清空临时日志"){ (m.state.raw["logText"] as? String ?? "x").isEmpty }
        await withCheckedContinuation { continuation in m.finish { continuation.resume() } }
        let reopened = Manager()
        do {
            try reopened.startSession(executable:URL(fileURLWithPath:"/usr/bin/sandbox-exec"),arguments:arguments,params:params,environment:environment)
            try await LocalPrism.wait(reopened,"重开加载器"){ reopened.state.ready }
            try require(reopened.state.packages.map(\.id) == expected,"加载器重开后顺序丢失")
            try await MarketplaceCheck.run(reopened,support:support)
            if let path = ProcessInfo.processInfo.environment["PACKPIER_SKILL_FIXTURE"] {
                reopened.readFile(URL(fileURLWithPath:path))
                try await LocalPrism.wait(reopened,"Skill ZIP"){ reopened.preview?.name == "packpier-greeting" }
                reopened.confirmImport()
                try await LocalPrism.wait(reopened,"Skill build",seconds:45) {
                    reopened.state.packages.contains { $0.id == "packpier-greeting" && $0.builtCurrent && $0.hasBuild && reopened.state.hasEnabled($0.id) }
                }
                print("PASS copied Skill example imported and compiled by isolated official loader")
            }
        } catch {
            await withCheckedContinuation { continuation in reopened.finish { continuation.resume() } }
            throw error
        }
        await withCheckedContinuation { continuation in reopened.finish { continuation.resume() } }
        print("PASS official loader: tied ranks, first/last placement, dependency rejection, order after restart, update channel, language, log refresh/clear")
    }
}
