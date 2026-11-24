import Foundation
import Darwin

typealias Object = [String: Any]

struct LibraryError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private func readObject(_ file: URL) throws -> Object {
    guard let result = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? Object else {
        throw LibraryError("Invalid JSON object in " + file.lastPathComponent)
    }
    return result
}

private struct InstalledPlugin {
    let id: String
    let directory: URL
    let manifest: Object
    let adapter: Object
    let priority: Int
    let dependencies: [String]
    var dependencyError: String?

    init(directory: URL, overrides: Object, bundledManifests: [String: Object] = [:]) throws {
        let file = directory.appendingPathComponent("package.json")
        guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
            throw LibraryError("Unexpected manifest symlink")
        }
        let stored = try readObject(file)
        guard let id = stored["name"] as? String, !id.isEmpty else { throw LibraryError("Missing package name") }
        let manifest = bundledManifests[id] ?? stored
        guard manifest["name"] as? String == id,
              let version = manifest["version"] as? String, !version.isEmpty,
              let adapter = (manifest["packpier"] ?? manifest["codexTweaks"]) as? Object,
              adapter["apiVersion"] as? Int == 3 else {
            throw LibraryError("Invalid plugin manifest in " + directory.lastPathComponent)
        }
        self.id = id
        self.directory = directory
        self.manifest = manifest
        self.adapter = adapter
        priority = (overrides[id] as? Object)?["priorityOverride"] as? Int ?? adapter["priority"] as? Int ?? 0
        dependencies = Array((adapter["packageDependencies"] as? Object ?? [:]).keys)
    }
}

final class PluginLibrary {
    private let root: URL
    private let lock: Int32

    private let bundledManifests: [String: Object]

    init(root: URL, bundled: URL? = nil) throws {
        var manifests: [String: Object] = [:]
        if let bundled {
            for id in BuiltInPackages.ids {
                let plugin = try InstalledPlugin(directory: bundled.appendingPathComponent(id), overrides: [:])
                guard plugin.id == id else { throw LibraryError("Invalid bundled package " + id) }
                manifests[id] = plugin.manifest
            }
        }
        self.bundledManifests = manifests
        self.root = root
        guard try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
            throw LibraryError("Choose a migrated Packpier library directory")
        }
        let path = root.appendingPathComponent(".packpier.lock").path
        let fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw LibraryError("Cannot open library lock") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw LibraryError("The library is in use")
        }
        lock = fd
        try finishPendingRemoval()
    }

    deinit { close(lock) }

    private func config(_ name: String) throws -> Object {
        let file = root.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: file.path) { return [:] }
        return try readObject(file)
    }

    private func persist(_ obj: Object, to name: String) throws {
        try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent(name), options: .atomic)
    }

    private func plugins(settings: Object) throws -> [InstalledPlugin] {
        let folder = root.appendingPathComponent("packages")
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let folders = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
        var remaining: [InstalledPlugin] = []
        var ids = Set<String>()
        for directory in folders {
            let info = try directory.resourceValues(forKeys: keys)
            guard info.isSymbolicLink != true else { throw LibraryError("Unexpected plugin symlink") }
            guard info.isDirectory == true else { continue }
            let plugin = try InstalledPlugin(directory: directory, overrides: settings["packages"] as? Object ?? [:], bundledManifests: bundledManifests)
            guard ids.insert(plugin.id).inserted else { throw LibraryError("Duplicate plugin: " + plugin.id) }
            remaining.append(plugin)
        }
        remaining.sort { ($0.priority, $0.id) < ($1.priority, $1.id) }
        var sorted: [InstalledPlugin] = []
        var loaded = Set<String>()
        while !remaining.isEmpty {
            guard let i = remaining.firstIndex(where: { loaded.isSuperset(of: $0.dependencies) }) else {
                for var blocked in remaining {
                    let unresolved = blocked.dependencies.filter { !loaded.contains($0) }.sorted()
                    blocked.dependencyError = "Missing or circular plugin dependency: " + unresolved.joined(separator: ", ")
                    sorted.append(blocked)
                }
                break
            }
            let plugin = remaining.remove(at: i)
            loaded.insert(plugin.id)
            sorted.append(plugin)
        }
        return sorted
    }

    // Only dependencies already selected in topological order can satisfy a window effect.
    private func windowPlan(_ plugins: [InstalledPlugin], disabled: Set<String>)
        -> (ids: [String], errors: [String: String]) {
        var available = Set<String>()
        var ids: [String] = []
        var errors: [String: String] = [:]
        for plugin in plugins where BuiltInPackages.ids.contains(plugin.id) && !disabled.contains(plugin.id) {
            if let issue = plugin.dependencyError {
                errors[plugin.id] = issue
                continue
            }
            let missing = plugin.dependencies.filter { !available.contains($0) }.sorted()
            if missing.isEmpty {
                available.insert(plugin.id)
                ids.append(plugin.id)
            } else {
                errors[plugin.id] = "Unavailable window effect dependencies: " + missing.joined(separator: ", ")
            }
        }
        return (ids, errors)
    }

    func state() throws -> Object {
        let settings = try config("package-settings.json")
        let state = try config("app-state.json")
        let ordered = try plugins(settings: settings)
        let enabled = state["enabled"] as? Bool == true
        let disabled = state["disabledPackageIDs"] as? [String] ?? []
        let errors = enabled ? windowPlan(ordered, disabled: Set(disabled)).errors : [:]
        let items = ordered.map { plugin -> Object in
            var row: Object = ["id": plugin.id, "manifest": plugin.manifest,
                "directory": plugin.directory.path, "priority": plugin.priority,
                "packageDependencies": plugin.adapter["packageDependencies"] ?? Object(),
                "availableActions": ["build": false, "authorizeNode": false, "delete": !BuiltInPackages.ids.contains(plugin.id),
                    "export": sourceArchive(for: plugin) != nil],
                "node": ["running": false, "authorized": false]]
            if let issue = plugin.dependencyError { row["validationError"] = issue }
            if let override = (settings["packages"] as? Object)?[plugin.id] as? Object {
                row["priorityOverride"] = override["priorityOverride"]
                row["approvedNodeSource"] = override["approvedNodeSource"]
            }
            // First-party window effects are compiled into Packpier at app build time, so they
            // are always current; there is no separate package build step in this loader.
            if BuiltInPackages.ids.contains(plugin.id), plugin.adapter["entrypoints"] is Object {
                row["activeBuild"] = ["kind": "bundled", "version": plugin.manifest["version"] ?? ""]
                row["buildDisposition"] = "current"
            }
            return row
        }
        return ["packages": items, "disabledPackageIDs": disabled, "packagePayloadErrors": errors,
                "enabled": enabled, "status": ["kind": enabled ? "checkingHost" : "disabled"]]
    }

    // A window needs only the ordered identifiers of active, compiled-in effects.
    func windowEffects() throws -> Object {
        let state = try config("app-state.json")
        guard state["enabled"] as? Bool == true else { return ["packages": [], "enabled": false] }
        let disabled = Set(state["disabledPackageIDs"] as? [String] ?? [])
        let ordered = try plugins(settings: config("package-settings.json"))
        let plan = windowPlan(ordered, disabled: disabled)
        return ["packages": plan.ids.map { ["id": $0] }, "enabled": true]
    }

    /// Enabled, dependency-safe window packages with their stable Node data directories.
    func windowHostPlan() throws -> (enabled: Bool, packages: [[String: Any]]) {
        let state = try config("app-state.json")
        let enabled = state["enabled"] as? Bool == true
        guard enabled else { return (false, []) }
        let disabled = Set(state["disabledPackageIDs"] as? [String] ?? [])
        let ordered = try plugins(settings: config("package-settings.json"))
        let plan = windowPlan(ordered, disabled: disabled)
        let data = root.appendingPathComponent("node-data")
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let packages: [[String: Any]] = plan.ids.map { id in
            let directory = data.appendingPathComponent(Self.fingerprint(id))
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return ["id": id, "dataDirectory": directory.path]
        }
        return (true, packages)
    }

    /// FNV-1a string fingerprint, matching the stable Node data directory names used by the
    /// upstream Codex Tweaks loader so existing Prism preferences keep their location.
    static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    // Moving the package out of discovery commits the uninstall. Keep its manifest intact
    // until both preference files are updated, so an interrupted operation can be replayed.
    private var removing: URL { root.appendingPathComponent(".packpier-removing") }
    private var removed: URL { root.appendingPathComponent(".packpier-removed") }

    func finishPendingRemoval() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: removed.path) { try fm.removeItem(at: removed) }
        guard fm.fileExists(atPath: removing.path) else { return }
        guard try removing.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isSymbolicLink == false else {
            throw LibraryError("Invalid pending plugin removal")
        }
        let package = try InstalledPlugin(directory: removing, overrides: [:])
        let id = package.id
        guard !BuiltInPackages.ids.contains(id) else { throw LibraryError("内置插件不能删除。") }
        var state = try config("app-state.json")
        var changed = false
        for key in ["knownPackageIDs", "disabledPackageIDs"] {
            if let ids = state[key] as? [String], ids.contains(id) {
                state[key] = ids.filter { $0 != id }
                changed = true
            }
        }
        if changed { try persist(state, to: "app-state.json") }
        var settings = try config("package-settings.json")
        if var overrides = settings["packages"] as? Object, overrides.removeValue(forKey: id) != nil {
            settings["packages"] = overrides
            try persist(settings, to: "package-settings.json")
        }
        try fm.moveItem(at: removing, to: removed)
        try fm.removeItem(at: removed)
    }

    func removePackage(_ id: String) throws {
        guard !BuiltInPackages.ids.contains(id) else { throw LibraryError("内置插件不能删除。") }
        let folder = root.appendingPathComponent("packages")
        guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
            throw LibraryError("Unexpected package directory symlink")
        }
        let installed = try plugins(settings: config("package-settings.json"))
        guard let package = installed.first(where: { $0.id == id }) else { return }
        guard !BuiltInPackages.ids.contains(package.directory.lastPathComponent.lowercased()) else {
            throw LibraryError("内置插件不能删除。")
        }
        try FileManager.default.moveItem(at: package.directory, to: removing)
        try finishPendingRemoval()
    }

    // Imported packages remain data. Only effects compiled into the application can run.
    func installArchive(_ source: URL) throws {
        let archive = try LocalPackage(source: source)
        guard !BuiltInPackages.ids.contains(archive.name) else { throw LibraryError("内置插件由 Packpier 更新。") }
        let installed = try plugins(settings: config("package-settings.json"))
        if let old = installed.first(where: { $0.id == archive.name }) {
            guard old.manifest["version"] as? String == archive.version else { throw LibraryError("已安装其他版本。") }
            return
        }
        let fm = FileManager.default
        let folder = root.appendingPathComponent("packages")
        let stage = folder.appendingPathComponent(".import-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        try archive.manifestData.write(to: stage.appendingPathComponent("package.json"))
        try fm.copyItem(at: archive.url, to: stage.appendingPathComponent(".packpier-source.zip"))
        try fm.moveItem(at: stage, to: folder.appendingPathComponent("local-" + Self.fingerprint(archive.name)))
    }

    private func sourceArchive(for plugin: InstalledPlugin) -> URL? {
        let url = plugin.directory.appendingPathComponent(".packpier-source.zip")
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink == false ? url : nil
    }

    func exportArchive(id: String, to destination: URL) throws {
        guard destination.pathExtension.lowercased() == "zip",
              !destination.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path + "/"),
              let plugin = try plugins(settings: config("package-settings.json")).first(where: { $0.id == id }),
              let archive = sourceArchive(for: plugin) else { throw LibraryError("没有可导出的源 ZIP。") }
        try Data(contentsOf: archive, options: .mappedIfSafe).write(to: destination, options: .atomic)
    }

    func setEnabled(_ enabled: Bool, id: String?) throws {
        var state = try config("app-state.json")
        if let id {
            guard try plugins(settings: config("package-settings.json")).contains(where: { $0.id == id }) else {
                throw LibraryError("Unknown plugin: " + id)
            }
            var disabled = state["disabledPackageIDs"] as? [String] ?? []
            disabled.removeAll { $0 == id }
            if !enabled { disabled.append(id) }
            state["disabledPackageIDs"] = disabled
        } else {
            state["enabled"] = enabled
        }
        try persist(state, to: "app-state.json")
    }

    func approveNodeSource(_ token: String, id: String) throws {
        guard !BuiltInPackages.ids.contains(id) else { throw LibraryError("Built-in plugin has no Node backend") }
        var settings = try config("package-settings.json")
        var packages = settings["packages"] as? Object ?? [:]
        var package = packages[id] as? Object ?? [:]
        package["approvedNodeSource"] = token
        packages[id] = package
        settings["packages"] = packages
        try persist(settings, to: "package-settings.json")
    }

    func nodeDataDirectory(_ id: String) throws -> URL {
        let fm = FileManager.default
        var folder = root
        for part in ["node-data", Self.fingerprint(id)] {
            folder.appendPathComponent(part, isDirectory: true)
            if !fm.fileExists(atPath: folder.path) {
                try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
            let traits = try folder.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard traits.isDirectory == true, traits.isSymbolicLink == false else { throw LibraryError("Invalid plugin data directory") }
        }
        return folder
    }

    func setOrder(_ ids: [String]) throws {
        var config = try config("package-settings.json")
        let installed = try plugins(settings: config)
        guard ids.count == installed.count, Set(ids) == Set(installed.map(\.id)) else {
            throw LibraryError("The order must include each installed plugin once")
        }
        let positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        var overrides = config["packages"] as? Object ?? [:]
        for plugin in installed {
            let index = positions[plugin.id]!
            guard plugin.dependencyError == nil, plugin.dependencies.allSatisfy({ (positions[$0] ?? ids.count) < index }) else {
                throw LibraryError("A dependency must precede " + plugin.id)
            }
            var entry = overrides[plugin.id] as? Object ?? [:]
            entry["priorityOverride"] = index * 16
            overrides[plugin.id] = entry
        }
        config["packages"] = overrides
        try persist(config, to: "package-settings.json")
    }
}
