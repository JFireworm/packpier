import AppKit

/// Observes the app independently of whether any plugin has mounted in its window.
@MainActor final class CodexStartup {
    static let bundleID = CodexListener.bundleID
    private var monitor: Task<Void, Never>?
    private(set) var message = "正在检测 Codex"

    func stop() {
        monitor?.cancel()
        monitor = nil
        message = "正在检测 Codex"
    }

    func start(report: @escaping @MainActor (String) -> Void) {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            var mayLaunch = true
            var absentMessage = "Codex 未运行"
            repeat {
                let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
                    .filter { !$0.isTerminated }
                var next: String
                if let app = running.first(where: { $0.isFinishedLaunching }) {
                    absentMessage = "Codex 未运行"
                    let pid = app.processIdentifier
                    let status = await Task.detached(priority: .utility) {
                        CodexListener.inspect(pid)
                    }.value
                    next = status.rawValue
                } else if !running.isEmpty {
                    next = "正在启动 Codex"
                } else if mayLaunch {
                    next = await Self.launchIfInstalled()
                    if next != "正在启动 Codex" { absentMessage = next }
                } else {
                    next = absentMessage
                }
                // Launch once on activation. Respect a subsequent deliberate quit.
                mayLaunch = false
                guard !Task.isCancelled else { return }
                if self?.message != next {
                    self?.message = next
                    report(next)
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            } while !Task.isCancelled
        }
    }

    private static func launchIfInstalled() async -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return "未找到 Codex 应用"
        }
        return await open(url) ? "正在启动 Codex" : "未能启动 Codex"
    }

    private static func open(_ url: URL) async -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.createsNewApplicationInstance = false
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                continuation.resume(returning: app != nil && error == nil)
            }
        }
    }

    static func restart(report: (String) -> Void) async throws {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
        guard apps.count == 1, let app = apps.first, let url = app.bundleURL else {
            throw PackpierError.message("Codex 运行状态已变化，请查看连接详情。")
        }
        let pid = app.processIdentifier
        let status = await Task.detached(priority: .utility) { CodexListener.inspect(pid) }.value
        try Task.checkCancellation()
        guard status == .missing, !app.isTerminated else {
            throw PackpierError.message("Codex 运行状态已变化，请查看连接详情。")
        }
        report("正在等待 Codex 退出…")
        guard app.terminate() else { throw PackpierError.message("Codex 尚未退出，请先处理保存提示。") }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(20))
        while !app.isTerminated {
            guard clock.now < deadline else { throw PackpierError.message("Codex 尚未退出，请先处理保存提示。") }
            try await Task.sleep(for: .milliseconds(200))
        }
        try Task.checkCancellation()
        report("正在启动 Codex")
        guard await open(url) else { throw PackpierError.message("未能启动 Codex") }
    }
}
