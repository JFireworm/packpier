import Foundation

/// Operations are injected so tests can exercise process replacement and deadlines without opening an app.
@MainActor
struct CodexRestart {
    let requestQuit: () -> Bool
    let runningPIDs: () -> [pid_t]
    let open: () async -> pid_t?
    let endpointReady: (pid_t) async -> Bool
    let ready: (pid_t) async -> Bool
    var forceQuit: () -> Void = {}
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) }

    func run(reusing existingPID: pid_t? = nil, report: (String) -> Void) async throws {
        try Task.checkCancellation()
        let pid: pid_t
        if let existingPID {
            pid = existingPID
        } else {
            let initial = runningPIDs()
            if !initial.isEmpty {
                report("正在等待 Codex 退出…")
                _ = requestQuit()
                if try await !waitForExit(initial, timeout: 5) {
                    forceQuit()
                    guard try await waitForExit(initial, timeout: 3) else {
                        throw PackpierError.message("Codex 未能正常退出，请手动退出后重试。")
                    }
                }
            }
            try Task.checkCancellation()
            guard runningPIDs().isEmpty else { throw changed() }
            report("正在启动 Codex")
            guard let opened = await open() else { throw PackpierError.message("未能启动 Codex") }
            pid = opened
        }
        let deadline = now() + 20
        report("正在等待 Codex 连接端口…")
        try await waitFor(pid, until: deadline, check: endpointReady, failure: "Codex 已重新打开，连接端口尚未就绪。")
        report("正在连接 Codex 窗口…")
        try await waitFor(pid, until: deadline, check: ready, failure: "Codex 已重新打开，窗口仍未连接。")
    }

    private func waitForExit(_ original: [pid_t], timeout: TimeInterval) async throws -> Bool {
        let deadline = now() + timeout
        while true {
            try Task.checkCancellation()
            let current = runningPIDs()
            if current.isEmpty { return true }
            guard current.allSatisfy(original.contains) else { throw changed() }
            if now() >= deadline { return false }
            try await pause()
        }
    }

    private func waitFor(_ pid: pid_t, until deadline: TimeInterval, check: (pid_t) async -> Bool,
                         failure: String) async throws {
        repeat {
            try Task.checkCancellation()
            let current = runningPIDs()
            if !current.isEmpty && current != [pid] { throw changed() }
            if current == [pid], await check(pid) {
                try Task.checkCancellation()
                guard runningPIDs() == [pid] else { throw changed() }
                if now() <= deadline { return }
            }
            if now() < deadline { try await pause() }
        } while now() < deadline
        throw PackpierError.message(failure)
    }

    private func changed() -> PackpierError {
        .message("Codex 运行状态已变化，请查看连接详情。")
    }
}
