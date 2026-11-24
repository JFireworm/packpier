import Foundation

// Private stdio session. Storage access begins only after an explicit library selection.
if CommandLine.arguments.dropFirst().elementsEqual(["--verify-codex-listener"]) {
    guard let pid = CodexListener.owner() else { exit(1) }
    print(pid)
    exit(0)
}
var library: PluginLibrary?
let host = WindowHost()
let outputLock = NSLock()
let stateLock = NSRecursiveLock()
let nodeRunner = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/NodeRunner/runner.mjs")
let thirdPartyNodes = ThirdPartyNodes(runner: nodeRunner, onExit: publishState) { plugin, name, payload in
    write(["event": "nodeEvent", "data": ["plugin": plugin, "name": name, "payload": payload] as Object])
}

func write(_ object: Object) {
    guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
    data.append(10)
    outputLock.lock()
    defer { outputLock.unlock() }
    FileHandle.standardOutput.write(data)
}

/// The library state plus the live window-host status. The manager reads `status.kind` for the
/// connection label and `windowEffects.mounted` for the packages actually present in Codex.
func mergedState() throws -> Object {
    guard let library else { throw LibraryError("Initialize the library first") }
    var state = try library.state()
    thirdPartyNodes.decorate(&state)
    let report = host.status
    let kind = state["enabled"] as? Bool == true ? report.kind : "disabled"
    state["status"] = ["kind": kind, "message": report.message]
    let active = kind != "disabled"
    state["windowEffects"] = ["mounted": active ? report.mounted : [], "errors": active ? report.errors : [:],
                              "windows": active ? report.windows : [:]]
    state["packageRuntimeErrors"] = active ? report.errors : [:]
    return state
}

func syncHost() {
    guard let library, let plan = try? library.windowHostPlan() else { return }
    host.sync(enabled: plan.enabled, packages: plan.packages)
}

func publishState() {
    stateLock.lock()
    defer { stateLock.unlock() }
    if let state = try? mergedState() { write(["event": "state", "data": state]) }
}

func startHost() {
    host.start(onChange: publishState)
    syncHost()
}

func handle(_ message: Object) throws -> Object {
    let params = message["params"] as? Object ?? [:]
    let method = message["method"] as? String
    if method == "initialize" {
        guard library == nil, let path = params["libraryDirectory"] as? String, path.hasPrefix("/") else {
            throw LibraryError("Expected a Packpier libraryDirectory")
        }
        let root = URL(fileURLWithPath: path)
        if let bundled = params["bundledPackagesDirectory"] as? String {
            try PluginLibrary.prepareFirstInstall(at: root, bundled: URL(fileURLWithPath: bundled))
        }
        let candidate = try PluginLibrary(root: root, bundled: (params["bundledPackagesDirectory"] as? String).map { URL(fileURLWithPath: $0) })
        _ = try candidate.state()
        library = candidate
        startHost()
        try thirdPartyNodes.sync(library: candidate, reload: false)
        return try mergedState()
    }
    guard let library else { throw LibraryError("Initialize the library first") }
    try library.finishPendingRemoval()
    switch method {
    case "getWindowEffects":
        let report = host.status
        let enabled = try library.state()["enabled"] as? Bool == true
        return ["packages": enabled ? report.mounted.map { ["id": $0] } : [], "enabled": enabled]
    case "getWindowPlan":
        return try library.windowEffects()
    case "retryWindowHost":
        host.retry()
    case "getState", "reloadPackages": break
    case "authorizeNodePackage":
        guard let id = params["packageID"] as? String, let token = params["authorizationID"] as? String else {
            throw LibraryError("Missing package approval")
        }
        try thirdPartyNodes.approve(token, id: id, library: library)
    case "callNodePackage":
        guard let id = params["packageID"] as? String, let method = params["method"] as? String else {
            throw LibraryError("Missing package or method")
        }
        return ["value": try thirdPartyNodes.call(id, method: method, parameters: params["parameters"] ?? NSNull())]
    case "installLocalPackage":
        guard let path = params["sourcePath"] as? String, path.hasPrefix("/") else { throw LibraryError("Missing ZIP path") }
        try library.installArchive(URL(fileURLWithPath: path))
    case "exportPackage":
        guard let id = params["packageID"] as? String, let path = params["destinationPath"] as? String,
              path.hasPrefix("/") else { throw LibraryError("Missing export destination") }
        try library.exportArchive(id: id, to: URL(fileURLWithPath: path))
    case "deletePackage":
        guard let id = params["packageID"] as? String, !id.isEmpty else { throw LibraryError("Missing packageID") }
        try library.removePackage(id)
    case "setPackageOrder":
        guard let ids = params["packageIDs"] as? [String] else { throw LibraryError("Missing packageIDs") }
        try library.setOrder(ids)
    case "setPackageEnabled", "setEnabled":
        guard let enabled = params["enabled"] as? Bool else { throw LibraryError("Missing enabled flag") }
        var id: String?
        if method == "setPackageEnabled" {
            guard let name = params["packageID"] as? String else { throw LibraryError("Missing packageID") }
            id = name
        }
        try library.setEnabled(enabled, id: id)
    default: throw LibraryError("Unsupported operation")
    }
    syncHost()
    try thirdPartyNodes.sync(library: library, reload: method == "reloadPackages")
    return try mergedState()
}

while let line = readLine() {
    stateLock.lock()
    defer { stateLock.unlock() }
    var reply: Object = [:]
    do {
        guard let request = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? Object,
              let id = request["id"] as? Int else { throw LibraryError("Expected a request id") }
        reply["id"] = id
        reply["result"] = try handle(request)
    } catch {
        reply["error"] = ["message": error.localizedDescription]
    }
    write(reply)
}
host.shutdown()
stateLock.lock()
library = nil
thirdPartyNodes.shutdown()
stateLock.unlock()
