import Foundation

@main enum SystemNodeCheck {
    static func main() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("packpier-node-check-" + UUID().uuidString)
        try fm.createDirectory(at: home, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: home) }
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        for version in ["v22.2.0", "v22.10.0"] {
            try fm.createDirectory(at: nvm.appendingPathComponent(version), withIntermediateDirectories: true)
        }
        let paths = SystemNode.candidates(home: home, environment: ["PACKPIER_NODE": "/custom/node"]).map(\.path)
        precondition(paths.first == "/custom/node" && paths[4].hasSuffix("v22.10.0/bin/node"))
        precondition(paths.contains(home.path + "/.volta/bin/node") && paths.contains(home.path + "/.asdf/shims/node"))
        precondition(SystemNode.find(in: []) == nil)
        let versions = ["v20.19.1", "v22.13.0"]
        let bins = try versions.map { version -> URL in
            let file = home.appendingPathComponent(version)
            try Data(("#!/bin/sh\necho " + version + "\n").utf8).write(to: file)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            return file
        }
        precondition(SystemNode.find(in: bins) == bins[1])
        let root = home.appendingPathComponent("library")
        let ids = ["p-sign", "prism", "custom-background", "third-party", "renderer-only"]
        for id in ids {
            let dir = root.appendingPathComponent("packages").appendingPathComponent(id)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let entries = id == "renderer-only" ? ["renderer": "index.js"] : ["node": "backend.mjs"]
            let manifest: Object = ["name": id, "version": "1.0", "packpier": ["apiVersion": 3, "entrypoints": entries] as Object]
            try JSONSerialization.data(withJSONObject: manifest).write(to: dir.appendingPathComponent("package.json"))
        }
        let library = try PluginLibrary(root: root)
        try library.setEnabled(true, id: nil)
        try library.setEnabled(false, id: "third-party")
        var probes = 0
        let nodes = ThirdPartyNodes(runner: home, locate: { probes += 1; return nil }, event: { _, _, _ in })
        try nodes.sync(library: library, reload: false)
        precondition(probes == 0)
        try library.setEnabled(true, id: "third-party")
        try nodes.sync(library: library, reload: false)
        var state = try library.state()
        nodes.decorate(&state)
        let issues = (state["packages"] as? [Object] ?? []).filter { $0["validationError"] != nil }
        precondition(probes == 1 && issues.count == 1 && issues[0]["id"] as? String == "third-party")
        precondition(issues[0]["validationError"] as? String == "需要 Node.js 22+")
        nodes.shutdown()
        print("PASS system Node discovery and minimum version; missing Node affects only its enabled third-party package")
    }
}
