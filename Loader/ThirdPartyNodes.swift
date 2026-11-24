import Foundation

/// The manager's private stdio session owns these backends. Built-in window services stay native.
final class ThirdPartyNodes {
    private struct Slot {
        let version: String
        var source: NodeSource?
        var worker: NodeWorker?
        var issue: String?
    }
    private var slots: [String: Slot] = [:]
    private var executable: URL?
    private let runner: URL
    private let locate: () -> URL?
    private let onExit: () -> Void
    private let event: (String, String, Any) -> Void

    init(runner: URL, locate: @escaping () -> URL? = {
        SystemNode.find(in: SystemNode.candidates(home: FileManager.default.homeDirectoryForCurrentUser,
                                                 environment: ProcessInfo.processInfo.environment))
    }, onExit: @escaping () -> Void = {}, event: @escaping (String, String, Any) -> Void) {
        self.runner = runner
        self.locate = locate
        self.onExit = onExit
        self.event = event
    }

    private func stop(_ id: String) {
        slots.removeValue(forKey: id)?.worker?.stop()
    }

    func shutdown() {
        for id in Array(slots.keys) { stop(id) }
        executable = nil
    }

    func sync(library: PluginLibrary, reload: Bool) throws {
        if reload { shutdown() }
        let state = try library.state()
        guard state["enabled"] as? Bool == true else { shutdown(); return }
        let disabled = Set(state["disabledPackageIDs"] as? [String] ?? [])
        var active = Set<String>()
        for row in state["packages"] as? [Object] ?? [] {
            guard let id = row["id"] as? String, !BuiltInPackages.ids.contains(id), !disabled.contains(id),
                  row["validationError"] == nil, let manifest = row["manifest"] as? Object,
                  let adapter = (manifest["packpier"] ?? manifest["codexTweaks"]) as? Object,
                  let entries = adapter["entrypoints"] as? Object, entries["node"] != nil,
                  let directory = row["directory"] as? String, let version = manifest["version"] as? String else { continue }
            active.insert(id)
            if slots[id]?.version != version { stop(id) }
            if slots[id] == nil {
                var slot = Slot(version: version)
                do {
                    if executable == nil { executable = locate() }
                    guard executable != nil else { throw LibraryError(SystemNode.required) }
                    guard let entry = entries["node"] as? String, !entry.isEmpty else { throw LibraryError("Invalid Node entry") }
                    slot.source = try NodeSource(package: URL(fileURLWithPath: directory), manifest: manifest, path: entry)
                } catch { slot.issue = error.localizedDescription }
                slots[id] = slot
            }
            if let slot = slots[id], slot.issue == nil, slot.worker == nil, let source = slot.source,
               let executable, row["approvedNodeSource"] as? String == source.token {
                do {
                    let data = try library.nodeDataDirectory(id)
                    slots[id]?.worker = try NodeWorker(executable: executable, runner: runner, source: source, data: data, onExit: onExit) { [event] name, payload in
                        event(id, name, payload)
                    }
                } catch { slots[id]?.issue = error.localizedDescription }
            }
        }
        for id in Set(slots.keys).subtracting(active) { stop(id) }
        if slots.isEmpty { executable = nil }
    }

    func decorate(_ state: inout Object) {
        state["packages"] = (state["packages"] as? [Object] ?? []).map { original -> Object in
            var row = original
            let approval = row.removeValue(forKey: "approvedNodeSource") as? String
            guard let id = row["id"] as? String, let slot = slots[id] else { return row }
            let manifest = row["manifest"] as? Object ?? [:]
            let adapter = (manifest["packpier"] ?? manifest["codexTweaks"]) as? Object
            let nodePermission = (adapter?["permissions"] as? Object)?["node"] as? Object
            let authorized = slot.source.map { $0.token == approval } ?? false
            var info: Object = ["authorized": authorized, "running": slot.worker?.running == true,
                                "reason": nodePermission?["reason"] as? String ?? ""]
            if let issue = slot.issue { row["validationError"] = issue }
            else if let worker = slot.worker, !worker.running { info["lastError"] = "Node plugin has stopped" }
            if let source = slot.source, !authorized {
                info["authorizationID"] = source.token
                var actions = row["availableActions"] as? Object ?? [:]
                actions["authorizeNode"] = true
                row["availableActions"] = actions
            }
            row["node"] = info
            return row
        }
    }

    func approve(_ token: String, id: String, library: PluginLibrary) throws {
        guard let source = slots[id]?.source, source.token == token else { throw LibraryError("Plugin changed; review again") }
        try library.approveNodeSource(token, id: id)
    }

    func call(_ id: String, method: String, parameters: Any) throws -> Any {
        guard let worker = slots[id]?.worker else { throw LibraryError("Node plugin is not running") }
        do {
            return try worker.request(["type": "call", "method": method, "parameters": parameters])
        } catch let error as NodeTransportError {
            slots[id]?.issue = error.localizedDescription
            slots[id]?.worker = nil
            worker.stop()
            throw error
        }
    }
}
