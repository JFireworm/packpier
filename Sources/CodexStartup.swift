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
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.createsNewApplicationInstance = false
        let launched = await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                continuation.resume(returning: app != nil && error == nil)
            }
        }
        return launched ? "正在启动 Codex" : "未能启动 Codex"
    }
}
