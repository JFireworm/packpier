import Foundation

/// Native window host. Connects to Codex's own loopback DevTools endpoint, injects the
/// prebuilt renderer bundle, and answers the page's RPC calls from native services.
/// No external runtime (Node) is involved for the built-in effects.
final class WindowHost {
    struct Report {
        var kind = "waitingForHost"
        var message = ""
        var mounted: [String] = []
        var errors: [String: String] = [:]
        var windows: [String: [String]] = [:]
    }

    private final class Session {
        let targetID: String
        let page: CDPPage
        let injection: WindowInjection
        init(targetID: String, page: CDPPage) {
            self.targetID = targetID
            self.page = page
            injection = WindowInjection(page: page)
        }
    }

    private let lock = NSLock()
    private var report = Report()
    private var onChange: (() -> Void)?
    private var enabled = false
    private var packages: [[String: Any]] = []
    private var sessions: [String: Session] = [:]
    private var prism: PrismService?
    private var prismDirectory: String?
    private var background: BackgroundService?
    private let provider = BackgroundProvider()
    private var bundle: String?
    private let bundleVersion = "packpier-window-8"
    private var polling: Task<Void, Never>?
    private var stopped = false
    private var failures: [String: String] = [:]
    private var retryRequested = false
    private var serviceErrors: [String: String] = [:]

    var status: Report {
        lock.lock()
        defer { lock.unlock() }
        return report
    }

    @discardableResult
    func start(onChange: @escaping () -> Void) -> Bool {
        lock.lock()
        if polling != nil {
            lock.unlock()
            return true
        }
        self.onChange = onChange
        stopped = false
        lock.unlock()

        guard let resources = Self.locateResources() else {
            set(Report(kind: "waitingForHost", message: "缺少窗口宿主资源"))
            return false
        }
        bundle = try? String(contentsOf: resources.bundle, encoding: .utf8)
        guard bundle != nil else {
            set(Report(kind: "waitingForHost", message: "无法读取窗口渲染包"))
            return false
        }
        startPolling()
        return true
    }

    func sync(enabled: Bool, packages: [[String: Any]]) {
        lock.lock()
        if enabled != self.enabled || !Self.samePackages(packages, self.packages) {
            retryRequested = true
        }
        self.enabled = enabled
        self.packages = packages
        lock.unlock()
    }

    func retry() {
        lock.lock()
        retryRequested = true
        lock.unlock()
    }

    func shutdown() {
        lock.lock()
        stopped = true
        let task = polling
        polling = nil
        let live = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        task?.cancel()
        log("shutdown begin sessions=\(live.count)")
        let done = DispatchSemaphore(value: 0)
        Task {
            for session in live {
                do {
                    try await session.injection.close()
                    self.log("shutdown closed \(session.targetID)")
                } catch {
                    self.log("shutdown close failed \(session.targetID): \(error.localizedDescription)")
                }
            }
            done.signal()
        }
        let waited = done.wait(timeout: .now() + 4)
        log("shutdown wait \(waited == .success)")
        for session in live { session.page.close() }
    }

    private func startPolling() {
        lock.lock()
        defer { lock.unlock() }
        guard polling == nil, !stopped else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func log(_ message: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Packpier/native-host.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = ISO8601DateFormatter().string(from: Date()) + " " + message + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    private func tick() async {
        let (isEnabled, planned, bundleCode, isStopped, retry) = lock.withLock {
            let changed = retryRequested
            retryRequested = false
            return (enabled, packages, bundle, stopped, changed)
        }
        guard !isStopped else { return }
        if retry { failures.removeAll() }
        guard isEnabled else {
            await closeSessions()
            failures.removeAll()
            set(Report(kind: "disabled"))
            return
        }
        guard let bundleCode else {
            set(Report(kind: "waitingForHost", message: "缺少窗口渲染包"))
            return
        }
        guard !LoaderConflict.running() else {
            // Stand down without touching a page the other host may be using.
            for session in takeSessions() { session.page.close() }
            set(Report(kind: "loaderConflict", message: "另一个加载器正在运行"))
            return
        }

        reconcileServices(planned)
        guard CodexListener.owner() != nil, let targets = await CodexTargets.list() else {
            await closeSessions()
            failures.removeAll()
            set(Report(kind: "waitingForCDP", message: "未检测到可用的 Codex 本机连接"))
            return
        }

        let liveIDs = Set(targets.map(\.id))
        failures = failures.filter { liveIDs.contains($0.key) }
        let (remaining, removed) = lock.withLock {
            let removed = sessions.filter { !liveIDs.contains($0.key) || $0.value.page.isClosed }
            for id in removed.keys { sessions.removeValue(forKey: id) }
            return (sessions, removed)
        }
        var active = remaining
        for session in removed.values { session.page.close() }

        let packageIDs = planned.compactMap { jsonString($0["id"]) }
        for target in targets where failures[target.id] == nil {
            guard mayInject() else { return }
            let session: Session
            if let current = active[target.id] {
                session = current
            } else {
                let page = CDPPage(targetID: target.id, url: target.ws)
                session = Session(targetID: target.id, page: page)
                page.onBinding = { [weak self, weak session] request in
                    guard let self, let session else { return }
                    Task { await self.handle(request, from: session) }
                }
                do {
                    try await page.open()
                    let keep = lock.withLock {
                        guard !stopped && enabled else { return false }
                        sessions[target.id] = session
                        return true
                    }
                    guard keep else { page.close(); return }
                    active[target.id] = session
                    log("page open \(target.id)")
                } catch {
                    let detail = "open: " + error.localizedDescription
                    log("inject failed \(target.id) \(detail)")
                    failures[target.id] = detail
                    page.close()
                    continue
                }
            }
            do {
                try await session.injection.apply(bundle: bundleCode, version: bundleVersion, packages: packageIDs) {
                    self.log("\(target.id) " + $0)
                }
            } catch is CancellationError {
                return
            } catch {
                failures[target.id] = error.localizedDescription
            }
        }
        guard mayInject() else { return }
        publish(planned: packageIDs, active: active)
    }

    private func mayInject() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !stopped && enabled && !Task.isCancelled
    }

    private func takeSessions() -> [Session] {
        lock.lock()
        defer { lock.unlock() }
        let live = Array(sessions.values)
        sessions.removeAll()
        return live
    }

    private func publish(planned: [String], active: [String: Session]) {
        var mounted: Set<String> = []
        var windows: [String: [String]] = [:]
        var errors = serviceErrors
        for session in active.values where session.injection.connected && !session.page.isClosed {
            let injection = session.injection
            windows[session.targetID] = injection.mounted
            mounted.formUnion(injection.mounted)
            for (id, message) in injection.errors where errors[id] == nil { errors[id] = message }
        }
        let detail = failures.keys.sorted().compactMap { failures[$0] }.first
        let kind = detail != nil ? "error" : (windows.isEmpty ? "waitingForPage" : "connected")
        set(Report(kind: kind, message: detail ?? (windows.isEmpty ? "等待 Codex 页面" : ""),
                   mounted: planned.filter { mounted.contains($0) }, errors: errors, windows: windows))
    }

    private func reconcileServices(_ planned: [[String: Any]]) {
        let prismPlan = planned.first { jsonString($0["id"]) == "prism" }
        let directory = jsonString(prismPlan?["dataDirectory"]).flatMap { $0.isEmpty ? nil : $0 }
        lock.lock()
        let previous = prismDirectory
        prismDirectory = directory
        lock.unlock()
        if previous != directory {
            prism = directory.map {
                PrismService(codexRoot: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
                             dataDirectory: URL(fileURLWithPath: $0))
            }
        }
        if !planned.contains(where: { jsonString($0["id"]) == "custom-background" }) {
            background = nil
        } else if background == nil {
            background = BackgroundService(home: FileManager.default.homeDirectoryForCurrentUser)
        }
        serviceErrors.removeAll()
    }

    private func handle(_ request: JSONObject, from session: Session) async {
        let callID = jsonString(request["id"]) ?? String(describing: request["id"] ?? "")
        let plugin = jsonString(request["plugin"]) ?? ""
        let method = jsonString(request["method"]) ?? ""
        let parameters = jsonObject(request["parameters"]) ?? [:]
        do {
            let value = try await dispatch(plugin: plugin, method: method, parameters: parameters)
            try await resolve(callID, ok: true, value: value, on: session.page)
        } catch {
            try? await resolve(callID, ok: false, value: ["message": error.localizedDescription], on: session.page)
        }
    }

    private func dispatch(plugin: String, method: String, parameters: JSONObject) async throws -> Any {
        let allowed = lock.withLock {
            enabled && !stopped && packages.contains(where: { jsonString($0["id"]) == plugin })
        }
        guard allowed else { throw WireError.message("插件已停用") }
        switch plugin {
        case "prism":
            guard let prism else { throw WireError.message("Prism 数据目录尚未就绪") }
            switch method {
            case "snapshot":
                return try await prism.snapshot()
            case "update":
                guard let account = parameters["account"] as? String,
                      let operation = jsonObject(parameters["operation"]) else {
                    throw WireError.message("无效的侧栏设置")
                }
                let origin = parameters["origin"] ?? NSNull()
                let result = try await prism.update(account: account, operation: operation)
                await broadcastEvent("prism", "changed", ["origin": origin])
                return result
            default:
                throw WireError.message("Unsupported Prism method")
            }
        case "custom-background":
            guard background != nil else { throw WireError.message("背景服务尚未就绪") }
            switch method {
            case "network.request":
                guard let raw = parameters["url"] as? String, let url = URL(string: raw) else {
                    throw WireError.message("无效的图片地址")
                }
                return try await provider.lookup(url: url,
                                                 method: jsonString(parameters["method"]) ?? "GET",
                                                 responseType: jsonString(parameters["responseType"]) ?? "text",
                                                 timeoutMs: jsonDouble(parameters["timeoutMs"]) ?? 10000)
            case "image.upload":
                try await background?.upload(id: jsonString(parameters["id"]) ?? "",
                                             offset: jsonInt(parameters["offset"]) ?? -1,
                                             base64: jsonString(parameters["data"]) ?? "",
                                             cancel: jsonBool(parameters["cancel"]) ?? false)
                return [:]
            case "image.read":
                guard let background else { throw WireError.message("背景服务尚未就绪") }
                return try await background.read(file: jsonString(parameters["file"]) ?? "",
                                                 offset: jsonInt(parameters["offset"]) ?? -1)
            case "image.action":
                guard let background else { throw WireError.message("背景服务尚未就绪") }
                return try await background.action(jsonString(parameters["action"]) ?? "",
                                                   file: jsonString(parameters["file"]),
                                                   upload: jsonString(parameters["upload"]),
                                                   source: jsonString(parameters["source"]).flatMap(URL.init(string:)))
            default:
                throw WireError.message("Unsupported background method")
            }
        default:
            throw WireError.message("No native service for " + plugin)
        }
    }

    private func resolve(_ id: String, ok: Bool, value: Any, on page: CDPPage) async throws {
        let expression = "globalThis.__packpierResolve && globalThis.__packpierResolve(\(jsValue(id)), \(ok ? "true" : "false"), \(jsValue(value)))"
        try await page.evaluate(expression)
    }

    private func broadcastEvent(_ plugin: String, _ name: String, _ payload: Any) async {
        let active = lock.withLock { Array(sessions.values) }
        for session in active {
            try? await session.page.evaluate("globalThis.__packpierEvent && globalThis.__packpierEvent(\(jsValue(plugin)), \(jsValue(name)), \(jsValue(payload)))")
        }
    }

    private func closeSessions() async {
        for session in takeSessions() {
            try? await session.injection.close()
            session.page.close()
        }
    }

    private func set(_ next: Report) {
        lock.lock()
        let changed = next.kind != report.kind || next.mounted != report.mounted
            || next.errors != report.errors || next.windows != report.windows || next.message != report.message
        guard !stopped else { lock.unlock(); return }
        report = next
        let callback = onChange
        lock.unlock()
        if changed { callback?() }
    }

    private static func samePackages(_ lhs: [[String: Any]], _ rhs: [[String: Any]]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            guard jsonString(a["id"]) == jsonString(b["id"]),
                  jsonString(a["dataDirectory"]) == jsonString(b["dataDirectory"]) else { return false }
        }
        return true
    }

    private struct Resources { let bundle: URL }

    private static func locateResources() -> Resources? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let resources = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        let bundle = resources.appendingPathComponent("WindowHost/window-effects.js")
        guard FileManager.default.fileExists(atPath: bundle.path) else { return nil }
        return Resources(bundle: bundle)
    }
}

private func jsValue(_ value: Any) -> String {
    if value is NSNull { return "null" }
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value),
       let text = String(data: data, encoding: .utf8) {
        return text
    }
    if let data = try? JSONSerialization.data(withJSONObject: [value]),
       let text = String(data: data, encoding: .utf8) {
        return String(text.dropFirst().dropLast())
    }
    return "null"
}

enum CodexTargets {
    struct Target { let id: String; let ws: URL }

    static func list(timeout: TimeInterval = 2) async -> [Target]? {
        guard let url = URL(string: "http://127.0.0.1:9335/json/list") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 1
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONSerialization.jsonObject(with: data) as? [JSONObject] else { return nil }
        var targets: [Target] = []
        for item in list {
            guard jsonString(item["type"]) == "page",
                  jsonString(item["url"]) == "app://-/index.html",
                  let id = jsonString(item["id"]), !id.isEmpty,
                  id.range(of: #"\A[A-Za-z0-9-]+\z"#, options: .regularExpression) != nil,
                  let socket = jsonString(item["webSocketDebuggerUrl"]),
                  socket == "ws://127.0.0.1:9335/devtools/page/" + id,
                  let ws = URL(string: socket) else { continue }
            targets.append(Target(id: id, ws: ws))
        }
        return targets
    }
}
