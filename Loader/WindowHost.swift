import Foundation

/// Supervises the Node window host that mounts the first-party effects inside Codex windows.
/// The host owns the debug-port connection; this class only forwards the window plan and keeps
/// the last reported status so the loader can answer `getState` with a live connection kind.
final class WindowHost {
    struct Report {
        var kind = "waitingForHost"
        var message = ""
        var mounted: [String] = []
        var errors: [String: String] = [:]
        var windows: [String: [String]] = [:]
    }

    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var report = Report()
    private var lastSent = ""
    private var onChange: (() -> Void)?
    private var stopping = false

    var status: Report {
        lock.lock()
        defer { lock.unlock() }
        return report
    }

    /// Starts one host process. Returns false when the app bundle has no host resources
    /// (for example a bare development build) so the loader keeps working without injection.
    @discardableResult
    func start(onChange: @escaping () -> Void) -> Bool {
        lock.lock()
        guard process == nil else { lock.unlock(); return true }
        self.onChange = onChange
        lock.unlock()

        guard let node = Self.locateNode() else {
            set(.init(kind: "nodeMissing", message: "未找到 Node.js"))
            return false
        }
        guard let resources = Self.locateResources() else {
            set(.init(kind: "waitingForHost", message: "缺少窗口宿主资源"))
            return false
        }

        let child = Process()
        let pipe = Pipe()
        child.executableURL = node
        child.arguments = [resources.script.path, "--bundle", resources.bundle.path]
        var environment = ProcessInfo.processInfo.environment
        var path = environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        path = node.deletingLastPathComponent().path + ":" + path
        environment["PATH"] = path
        environment["PACKPIER_HOST_VERSION"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        child.environment = environment
        child.standardInput = Pipe()
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        input = (child.standardInput as? Pipe)?.fileHandleForWriting
        do {
            try child.run()
        } catch {
            set(.init(kind: "error", message: error.localizedDescription))
            return false
        }

        lock.lock()
        process = child
        stopping = false
        lock.unlock()

        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                self?.consume(data)
            }
            guard let self else { return }
            self.lock.lock()
            let wasStopping = self.stopping
            self.lock.unlock()
            if !wasStopping { self.set(.init(kind: "error", message: "窗口宿主已退出")) }
        }
        return true
    }

    /// Sends the enabled packages in display order. `packages` carries id and dataDirectory.
    func sync(enabled: Bool, packages: [[String: Any]]) {
        guard let input, process?.isRunning == true else { return }
        let message: [String: Any] = ["type": "sync", "enabled": enabled, "packages": packages]
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]) else { return }
        lock.lock()
        let signature = String(decoding: data, as: UTF8.self)
        guard signature != lastSent else { lock.unlock(); return }
        lastSent = signature
        lock.unlock()
        var line = data
        line.append(10)
        try? input.write(contentsOf: line)
    }

    func shutdown() {
        lock.lock()
        stopping = true
        let child = process
        let pipe = input
        lock.unlock()
        guard let child else { return }
        if child.isRunning {
            var line = Data(#"{"type":"shutdown"}"#.utf8)
            line.append(10)
            try? pipe?.write(contentsOf: line)
            try? pipe?.close()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
                if child.isRunning { child.terminate() }
            }
        }
    }

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var messages: [Data] = []
        while let index = buffer.firstIndex(of: 10) {
            messages.append(Data(buffer[..<index]))
            buffer.removeSubrange(...index)
        }
        lock.unlock()
        for message in messages { handle(message) }
    }

    private func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["event"] as? String == "windowState",
              let payload = object["data"] as? [String: Any],
              let kind = payload["kind"] as? String else { return }
        set(.init(kind: kind,
                  message: payload["message"] as? String ?? "",
                  mounted: payload["mounted"] as? [String] ?? [],
                  errors: payload["errors"] as? [String: String] ?? [:],
                  windows: payload["windows"] as? [String: [String]] ?? [:]))
    }

    private func set(_ next: Report) {
        lock.lock()
        let changed = next.kind != report.kind || next.mounted != report.mounted || next.errors != report.errors || next.windows != report.windows || next.message != report.message
        report = next
        let callback = onChange
        lock.unlock()
        if changed { callback?() }
    }

    // MARK: - Locations

    private struct Resources { let script: URL; let bundle: URL }

    private static func locateResources() -> Resources? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let helpers = executable.deletingLastPathComponent()
        let resources = helpers.deletingLastPathComponent().appendingPathComponent("Resources")
        let script = resources.appendingPathComponent("WindowHost/window-host.mjs")
        let bundle = resources.appendingPathComponent("WindowHost/window-effects.js")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: bundle.path) else { return nil }
        return Resources(script: script, bundle: bundle)
    }

    private static func locateNode() -> URL? {
        let fm = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["PACKPIER_NODE"], fm.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        var candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        let home = fm.homeDirectoryForCurrentUser
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fm.contentsOfDirectory(atPath: nvm.path) {
            for version in versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
                candidates.append(nvm.appendingPathComponent(version).appendingPathComponent("bin/node").path)
            }
        }
        candidates += [
            home.appendingPathComponent(".volta/bin/node").path,
            home.appendingPathComponent(".local/bin/node").path,
            home.appendingPathComponent(".asdf/shims/node").path,
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}