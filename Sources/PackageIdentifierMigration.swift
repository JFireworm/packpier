import Foundation

// Runs with the loader stopped. Move persistent user data, but never carry over a Node grant.
enum PackageIdentifierMigration {
    static let names = ["ct-prism":"prism", "ct-custom-background":"custom-background"]

    static func run(packages: URL, support: URL) throws {
        let fm = FileManager.default
        let dirs = try fm.contentsOfDirectory(at: packages, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        let state = packages.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("State")
        for (old, new) in names {
            let matches = dirs.filter { dir in
                guard let data = try? Data(contentsOf:dir.appendingPathComponent("package.json")),
                      let json = try? JSONSerialization.jsonObject(with:data) as? Fields else { return false }
                return json["name"] as? String == old || (dir.lastPathComponent == old && json["name"] as? String == new)
            }
            guard let source = matches.first else { continue }
            let target = packages.appendingPathComponent(new, isDirectory:true)
            guard matches.count == 1, source.path == target.path || !fm.fileExists(atPath:target.path) else {
                throw PackpierError.message("Conflicting plugin directories: " + old + ", " + new)
            }
            let backups = support.appendingPathComponent("Packpier/Backups/id-migration")
            try fm.createDirectory(at:backups, withIntermediateDirectories:true)
            let backup = backups.appendingPathComponent(old)
            if !fm.fileExists(atPath:backup.path) {
                let stage = backups.appendingPathComponent(UUID().uuidString)
                defer { try? fm.removeItem(at:stage) }
                try fm.copyItem(at:source,to:stage)
                try fm.moveItem(at:stage,to:backup)
            }
            let dataRoot = state.appendingPathComponent("NodeData")
            let from = dataRoot.appendingPathComponent(nodeKey(old)), to = dataRoot.appendingPathComponent(nodeKey(new))
            if fm.fileExists(atPath:from.path) { try fm.moveItem(at:from,to:to) }
            try changeJSON(state.appendingPathComponent("package-settings.json")) { json in
                guard var values = json["packages"] as? Fields, let setting = values.removeValue(forKey:old) else { return }
                if values[new] == nil { values[new] = setting }
                json["packages"] = values
            }
            try changeJSON(state.appendingPathComponent("app-state.json")) { json in
                for key in ["knownPackageIDs","disabledPackageIDs"] {
                    if let ids = json[key] as? [String], ids.contains(old) {
                        var seen = Set<String>()
                        json[key] = ids.map { $0 == old ? new : $0 }.filter { seen.insert($0).inserted }
                    }
                }
            }
            try changeJSON(source.appendingPathComponent("package-lock.json")) { json in
                if json["name"] as? String == old { json["name"] = new }
                if var all = json["packages"] as? Fields, var root = all[""] as? Fields, root["name"] as? String == old {
                    root["name"] = new; all[""] = root; json["packages"] = all
                }
            }
            try changeJSON(source.appendingPathComponent("package.json")) { $0["name"] = new }
            if source.path != target.path { try fm.moveItem(at:source,to:target) }
        }
    }

    // The loader uses 64-bit FNV-1a of the package ID for State/NodeData.
    private static func nodeKey(_ id: String) -> String {
        let hash = id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(format:"%016llx",hash)
    }

    private static func changeJSON(_ url: URL, edit: (inout Fields) -> Void) throws {
        guard FileManager.default.fileExists(atPath:url.path) else { return }
        guard var json = try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? Fields else {
            throw PackpierError.message("Invalid JSON object: " + url.lastPathComponent)
        }
        let original = json as NSDictionary
        edit(&json)
        if !original.isEqual(to:json) {
            try JSONSerialization.data(withJSONObject:json,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:url,options:.atomic)
        }
    }
}
