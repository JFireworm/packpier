import AppKit
import Darwin

/// Observes the app independently of whether any plugin has mounted in its window.
enum CodexLaunch {
    /// The same loopback-only DevTools contract Codex Tweaks uses. Packpier only ever
    /// launches Codex with these local arguments; it never rewrites the Codex bundle.
    static let arguments = [
        "--remote-debugging-address=127.0.0.1",
        "--remote-debugging-port=9335",
        "--remote-allow-origins=http://127.0.0.1:9335",
    ]
}

@MainActor final class CodexStartup {
    static let bundleID = CodexListener.bundleID
    private var monitor: Task<Void, Never>?
    private var pausedForRestart = false
    private var autoLaunchAllowed = true
    private(set) var message = "正在检测 Codex"

    func stop() {
        monitor?.cancel()
        monitor = nil
        message = "正在检测 Codex"
    }

    func pauseForRestart() {
        pausedForRestart = true
        autoLaunchAllowed = false
        stop()
    }

    func resumeAfterRestart() { pausedForRestart = false }

    func start(report: @escaping @MainActor (String) -> Void) {
        start(sample: Self.runningStatus, launch: Self.launchIfInstalled, report: report)
    }

    func start(sample: @escaping @MainActor () async -> String?,
               launch: @escaping @MainActor () async -> String,
               report: @escaping @MainActor (String) -> Void) {
        guard !pausedForRestart, monitor == nil else { return }
        monitor = Task { [weak self] in
            var absentMessage = "Codex 未运行"
            while !Task.isCancelled {
                let sample = await sample()
                guard !Task.isCancelled, let self else { return }
                var next: String
                let mayLaunch = autoLaunchAllowed
                autoLaunchAllowed = false
                if let sample {
                    absentMessage = "Codex 未运行"
                    next = sample
                } else if mayLaunch {
                    next = await launch()
                    if next != "正在启动 Codex" { absentMessage = next }
                } else {
                    next = absentMessage
                }
                guard !Task.isCancelled else { return }
                if message != next {
                    message = next
                    report(next)
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    private static func running() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
    }

    private static func runningStatus() async -> String? {
        let apps = running()
        if let app = apps.first(where: \.isFinishedLaunching) {
            return await inspect(app.processIdentifier).rawValue
        }
        return apps.isEmpty ? nil : "正在启动 Codex"
    }

    private static func inspect(_ pid: pid_t) async -> CodexListener.Status {
        await Task.detached(priority: .utility) { CodexListener.inspect(pid) }.value
    }

    private static func launchIfInstalled() async -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return "未找到 Codex 应用"
        }
        return await open(url) != nil ? "正在启动 Codex" : "未能启动 Codex"
    }

    private static func open(_ url: URL) async -> pid_t? {
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = CodexLaunch.arguments
        config.activates = false
        config.createsNewApplicationInstance = true
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                continuation.resume(returning: error == nil ? app?.processIdentifier : nil)
            }
        }
    }

    static func restart(report: (String) -> Void) async throws {
        let apps = running()
        let app = apps.first
        guard apps.count <= 1,
              let url = app?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw PackpierError.message("Codex 运行状态已变化，请查看连接详情。")
        }
        var existingPID: pid_t?
        if let app {
            let status = await inspect(app.processIdentifier)
            try Task.checkCancellation()
            guard status == .missing || status == .available,
                  running().map(\.processIdentifier) == [app.processIdentifier] else {
                throw PackpierError.message("Codex 运行状态已变化，请查看连接详情。")
            }
            if status == .available { existingPID = app.processIdentifier }
        }
        let workflow = CodexRestart(requestQuit: { app?.terminate() ?? false },
            runningPIDs: { running().map(\.processIdentifier) }, open: { await open(url) },
            endpointReady: { await inspect($0) == .available }, ready: { await CodexReadiness.ready(pid: $0) },
            forceQuit: {
                if let app, running().contains(where: { $0.processIdentifier == app.processIdentifier }) {
                    _ = app.forceTerminate()
                }
            })
        try await workflow.run(reusing: existingPID, report: report)
    }
}
