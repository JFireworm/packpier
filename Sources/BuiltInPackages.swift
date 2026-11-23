import Foundation

extension BuiltInPackages {
    // Seed source packages only. The loader owns builds, user settings and Node consent.
    static func prepare(resources: URL, support: URL) throws {
        let fm = FileManager.default
        let packages = support.appendingPathComponent("Codex Tweaks/Tweaks/packages", isDirectory: true)
        try fm.createDirectory(at: packages, withIntermediateDirectories: true)
        try PackageIdentifierMigration.run(packages:packages,support:support)
        var local: [String: URL] = [:]
        for url in try fm.contentsOfDirectory(at: packages, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            if let id = manifest(url)?["name"] as? String { local[id] = url }
        }
        for id in ids.sorted() {
            let source = resources.appendingPathComponent("BundledPlugins/" + id, isDirectory: true)
            guard let shipped = manifest(source), shipped["name"] as? String == id else {
                throw PackpierError.message("Missing bundled plugin: " + id)
            }
            let destination = local[id] ?? packages.appendingPathComponent(id, isDirectory: true)
            if local[id] != nil {
                guard let old = manifest(destination)?["version"] as? String,
                      let new = shipped["version"] as? String else { continue }
                let signUpdate = id == sign && old.compare(new, options: .numeric) == .orderedAscending
                let previousBackground = ["1.3.14", "1.3.15", "1.3.16"].contains(old) || old.range(of: #"^1\.3\.14-packpier\.[1-5]$"#, options: .regularExpression) != nil
                let backgroundRelease = id == "custom-background" && new == "1.3.17" && previousBackground
                let prismUpdate = id == "prism" && old == "0.1.11" && new == "0.1.12"
                guard signUpdate || prismUpdate || backgroundRelease else { continue }
            }
            let stage = packages.appendingPathComponent(".packpier-" + UUID().uuidString)
            defer { try? fm.removeItem(at: stage) }
            try fm.copyItem(at: source, to: stage)
            if local[id] == nil { try fm.moveItem(at: stage, to: destination) }
            else {
                let backup = support.appendingPathComponent("Packpier/Backups", isDirectory: true)
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                try fm.copyItem(at: destination, to: backup.appendingPathComponent(id + "-" + UUID().uuidString))
                _ = try fm.replaceItemAt(destination, withItemAt: stage)
            }
        }
    }
    private static func manifest(_ directory: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("package.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
