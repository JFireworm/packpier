import Darwin
import Foundation

extension PluginLibrary {
    /// Only publish a complete library. Opening an existing installation never re-seeds its settings.
    static func prepareFirstInstall(at root: URL, bundled: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: root.path) else { return }
        let parent = root.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stage = parent.appendingPathComponent(".packpier-install-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        let packages = stage.appendingPathComponent("packages")
        try fm.createDirectory(at: packages, withIntermediateDirectories: false)
        let order = [BuiltInPackages.sign, "prism", "custom-background"]
        var priorities: Object = [:]
        for (index, id) in order.enumerated() {
            let source = bundled.appendingPathComponent(id)
            let data = try Data(contentsOf: source.appendingPathComponent("package.json"))
            guard let manifest = try JSONSerialization.jsonObject(with: data) as? Object,
                  manifest["name"] as? String == id,
                  (manifest["packpier"] as? Object)?["apiVersion"] as? Int == 3 else {
                throw LibraryError("Invalid bundled manifest for " + id)
            }
            try fm.copyItem(at: source, to: packages.appendingPathComponent(id))
            priorities[id] = ["priorityOverride": index * 16]
        }
        try JSONSerialization.data(withJSONObject: ["enabled": true, "disabledPackageIDs": []] as Object)
            .write(to: stage.appendingPathComponent("app-state.json"))
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "packages": priorities] as Object)
            .write(to: stage.appendingPathComponent("package-settings.json"))
        if renamex_np(stage.path, root.path, UInt32(RENAME_EXCL)) != 0 {
            let code = errno
            guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
    }
}
