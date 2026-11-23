import Foundation

enum MarketplaceCheck {
    @MainActor static func run(_ m: Manager, support: URL) async throws {
        let app = ProcessInfo.processInfo.environment["PACKPIER_TEST_APP"] ?? "build/Packpier.app"
        guard let resources = Bundle(path:app)?.resourceURL else { throw PackpierError.message("Build Packpier before testing the packaged catalog") }
        let fresh = support.appendingPathComponent("builtin-check",isDirectory:true)
        try BuiltInPackages.prepare(resources:resources,support:fresh)
        let plugins = fresh.appendingPathComponent("Codex Tweaks/Tweaks/packages")
        guard Set(try FileManager.default.contentsOfDirectory(atPath:plugins.path)) == BuiltInPackages.ids else {
            throw PackpierError.message("Bundled plugin seed incomplete")
        }
        let marker = plugins.appendingPathComponent("prism/preserved.txt")
        try Data("local".utf8).write(to:marker)
        try BuiltInPackages.prepare(resources:resources,support:fresh)
        guard try Data(contentsOf:marker) == Data("local".utf8) else { throw PackpierError.message("Local plugin was overwritten") }
        for id in BuiltInPackages.ids {
            m.send("deletePackage",["packageID":id])
            guard m.error == "内置插件不能删除。" else { throw PackpierError.message("Deletion allowed: " + id) }
            m.error = nil
        }
        print("PASS fresh built-ins, repeat launch and three rejected deletes")
        let legacy = support.appendingPathComponent("old-id-check")
        let host = legacy.appendingPathComponent("Codex Tweaks")
        let oldPackage = host.appendingPathComponent("Tweaks/packages/ct-prism")
        let stateDir = host.appendingPathComponent("State")
        let oldPrefs = stateDir.appendingPathComponent("NodeData/c58e47c6245b42da")
        let fm = FileManager.default
        for dir in [oldPackage,oldPrefs] { try fm.createDirectory(at:dir,withIntermediateDirectories:true) }
        try Data(#"{"name":"ct-prism","version":"0.1.11"}"#.utf8).write(to:oldPackage.appendingPathComponent("package.json"))
        try Data("session colors".utf8).write(to:oldPrefs.appendingPathComponent("prefs"))
        try Data(#"{"disabledPackageIDs":["ct-prism"],"knownPackageIDs":["ct-prism","p-sign"]}"#.utf8).write(to:stateDir.appendingPathComponent("app-state.json"))
        try Data(#"{"packages":{"ct-prism":{"priorityOverride":23}}}"#.utf8).write(to:stateDir.appendingPathComponent("package-settings.json"))
        for _ in 0..<2 { try BuiltInPackages.prepare(resources:resources,support:legacy) }
        let config = try JSONSerialization.jsonObject(with:Data(contentsOf:stateDir.appendingPathComponent("app-state.json"))) as? Fields
        let order = try JSONSerialization.jsonObject(with:Data(contentsOf:stateDir.appendingPathComponent("package-settings.json"))) as? [String:[String:[String:Int]]]
        guard !fm.fileExists(atPath:oldPackage.path),
              config?["disabledPackageIDs"] as? [String] == ["prism"],
              config?["knownPackageIDs"] as? [String] == ["prism","p-sign"],
              order?["packages"]?["prism"]?["priorityOverride"] == 23,
              try Data(contentsOf:stateDir.appendingPathComponent("NodeData/2f4e9f248cb97922/prefs")) == Data("session colors".utf8)
        else { throw PackpierError.message("Legacy identifier migration failed") }
        print("PASS identifier migration and retry; kept preferences, disabled state and load order")
        let market = try Marketplace(directory:resources.appendingPathComponent("Marketplace"))
        guard market.packages(for:nil).count == market.entries.count,
              Set(market.packages(for:.codex).map(\.id)) == BuiltInPackages.ids,
              market.packages(for:.wechat).map(\.id) == ["wechat-celadon"], market.packages(for:.feishu).isEmpty,
              let entry = market.entries.first(where:{ $0.id == "custom-background" }) else {
            throw PackpierError.message("Incorrect marketplace filters")
        }
        for entry in market.entries where !entry.builtInCeladon {
            let file = try LocalPackage(source:market.archive(for:entry))
            guard file.name == entry.id, file.version == entry.version else { throw PackpierError.message("Incorrect catalog archive: " + entry.id) }
        }
        guard let sign = market.entries.first(where:{ $0.id == "p-sign" }) else {
            throw PackpierError.message("Missing P-Sign")
        }
        m.prepareMarketInstall(sign,from:market)
        try await LocalPrism.wait(m,"P-Sign ZIP"){ m.preview?.name == sign.id }
        guard m.preview?.reason == nil else { throw PackpierError.message("P-Sign must be renderer-only") }
        m.confirmImport()
        try await LocalPrism.wait(m,"P-Sign compilation"){
            m.state.packages.contains { $0.id == sign.id && $0.builtCurrent && $0.hasBuild } && !m.transferBusy
        }
        m.page = "插件市场"
        m.prepareMarketInstall(entry,from:market)
        try await LocalPrism.wait(m,"市场确认面板"){ m.preview?.name == entry.id }
        guard m.page == "插件市场" && !m.state.packages.contains(where:{ $0.id == entry.id }) else { throw PackpierError.message("Market installation skipped confirmation") }
        m.confirmImport()
        func installed() -> TweakPackage? { m.state.packages.first { $0.id == entry.id && $0.version == entry.version && $0.builtCurrent } }
        try await LocalPrism.wait(m,"从市场安装并编译"){ installed() != nil && !m.transferBusy }
        guard let pkg = m.state.packages.first(where: { $0.id == "ct-b" }), m.canExport(pkg) else { throw PackpierError.message("Installed package has no export action") }
        let zip = support.appendingPathComponent("导出的插件.zip")
        let sentinel = Data("previous file".utf8)
        try sentinel.write(to:zip)
        m.exportPackage(pkg.id,to:zip)
        try await LocalPrism.wait(m,"导出源码 ZIP",seconds:10){ m.exportingID == nil && !m.notice.isEmpty }
        let exported = try LocalPackage(source:zip)
        guard exported.name == pkg.id && exported.version == pkg.version else { throw PackpierError.message("Exported ZIP manifest mismatch") }
        // Exercise failure on the official exporter without altering the existing archive.
        let before = try Data(contentsOf:zip)
        m.exportPackage(pkg.id,to:support.appendingPathComponent("missing-dir/broken.zip"))
        try await LocalPrism.wait(m,"导出失败回执",seconds:10){ m.exportingID == nil && m.error != nil }
        m.error = nil
        guard try Data(contentsOf:zip) == before else { throw PackpierError.message("Export failure overwrote the previous ZIP") }

        let isolatedRoot = support.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard URL(fileURLWithPath:pkg.directory).resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(isolatedRoot) else {
            throw PackpierError.message("Round-trip test requires an isolated installation")
        }
        guard m.canRemovePlugin(pkg), !m.state.packages.filter({ BuiltInPackages.ids.contains($0.id) }).contains(where: m.canRemovePlugin) else {
            throw PackpierError.message("Incorrect plugin removal availability")
        }
        m.removePlugin(pkg.id)
        try await LocalPrism.wait(m,"清理隔离测试副本"){ !m.state.packages.contains(where:{ $0.id == pkg.id }) && !m.transferBusy }
        m.readFile(zip)
        try await LocalPrism.wait(m,"重导入导出的 ZIP"){ m.preview?.name == pkg.id }
        m.confirmImport()
        try await LocalPrism.wait(m,"重新编译导出的插件"){ m.state.packages.contains { $0.id == pkg.id && $0.builtCurrent } && m.state.hasEnabled(pkg.id) }
        print("PASS marketplace app filters; \(market.entries.count) catalog entries including built-in Celadon; selection and consent; official install and build; overwrite export, failure feedback, fresh re-import and rebuild of \(pkg.id) \(pkg.version)")
    }
}
