import Foundation

/// Operations are injected so tests can exercise process replacement and deadlines without opening an app.
@MainActor
struct CodexRestart {
    let requestQuit: () -> Bool
    let oldProcessExited: () -> Bool
    let runningPIDs: () -> [pid_t]
    let open: () async -> pid_t?
    let ready: (pid_t) async -> Bool
    var forceQuit: () -> Void = {}
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) }

    func run(report: (String) -> Void) async throws {
        try Task.checkCancellation()
        report("正在等待 Codex 退出…")
        guard requestQuit() else { throw PackpierError.message("Codex 尚未退出，请先处理保存提示。") }
        let exitDeadline = now() + 5
        while !oldProcessExited() {
            try Task.checkCancellation()
            guard now() < exitDeadline else {
                // Graceful quit timed out: ask the system to end the process, then give it
                // three more seconds before reporting a failure to the user.
                forceQuit()
                let forceDeadline = now() + 3
                while !oldProcessExited() {
                    try Task.checkCancellation()
                    guard now() < forceDeadline else {
                        throw PackpierError.message("Codex 未能正常退出，请手动退出后重试。")
                    }
                    try await pause()
                }
                break
            }
            try await pause()
        }
        try Task.checkCancellation()
        guard runningPIDs().isEmpty else { throw PackpierError.message("Codex 运行状态已变化，请查看连接详情。") }
        report("正在启动 Codex")
        guard let pid = await open() else { throw PackpierError.message("未能启动 Codex") }
        report("正在连接 Codex")
        let readyDeadline = now() + 20
        while now() < readyDeadline {
            try Task.checkCancellation()
            let current = runningPIDs()
            if !current.isEmpty && current != [pid] {
                throw PackpierError.message("Codex 运行状态已变化，请查看连接详情。")
            }
            if current == [pid], await ready(pid), now() <= readyDeadline, runningPIDs() == [pid] { return }
            if now() < readyDeadline { try await pause() }
        }
        throw PackpierError.message("Codex 已重新打开，窗口仍未连接。")
    }
}
