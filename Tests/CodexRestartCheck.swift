import Foundation

@MainActor enum CodexRestartCheck {
    private enum Scenario { case success, refused, timeout, replacement, missingPage, pidChanged, cancelled }

    static func run() async throws {
        for scenario: Scenario in [.success, .refused, .timeout, .replacement, .missingPage, .pidChanged, .cancelled] {
            var time = 0.0
            var opens = 0
            var reads = 0
            var messages: [String] = []
            var forced = 0
            let flow = CodexRestart(requestQuit: { scenario != .refused },
                oldProcessExited: { scenario != .timeout && time >= 1 },
                runningPIDs: {
                    if opens == 0 { return scenario == .replacement ? [222] : [] }
                    return scenario == .pidChanged && reads > 0 ? [333] : [111]
                }, open: { opens += 1; return 111 }, ready: { pid in
                    precondition(pid == 111)
                    reads += 1
                    return scenario != .missingPage && reads >= 2
                }, forceQuit: { forced += 1 }, now: { time }, pause: {
                    if scenario == .cancelled { throw CancellationError() }
                    time += 0.25
                })
            var failure: Error?
            do { try await flow.run { messages.append($0) } } catch { failure = error }
            switch scenario {
            case .success:
                precondition(failure == nil && opens == 1 && reads == 2)
                precondition(messages == ["正在等待 Codex 退出…", "正在启动 Codex", "正在连接 Codex"])
            case .refused:
                precondition(failure?.localizedDescription == "Codex 尚未退出，请先处理保存提示。" && opens == 0)
                precondition(time == 0 && forced == 0)
            case .timeout:
                precondition(failure?.localizedDescription == "Codex 未能正常退出，请手动退出后重试。" && opens == 0)
                precondition(time == 8 && forced == 1)
            case .replacement, .pidChanged:
                precondition(failure?.localizedDescription == "Codex 运行状态已变化，请查看连接详情。")
                precondition(opens == (scenario == .replacement ? 0 : 1))
            case .missingPage:
                precondition(failure?.localizedDescription == "Codex 已重新打开，窗口仍未连接。" && time == 21 && opens == 1)
            case .cancelled:
                precondition(failure is CancellationError && opens == 0)
            }
        }
        for (type, url, expected) in [
            ("page", "app://-/index.html", true), ("page", "app://-/index.html?view=main", true),
            ("page", "app://-/index.html?view=avatar%2Doverlay", false), ("iframe", "app://-/index.html", false),
            ("page", "https://example.com/index.html", false), ("page", "app://u@-/index.html", false)
        ] {
            let data = try JSONSerialization.data(withJSONObject: [["type": type, "url": url]])
            precondition(CodexReadiness.hasMainPage(data) == expected)
        }
        precondition(!CodexReadiness.hasMainPage(Data("{}".utf8)))
        precondition(CodexLaunch.arguments == ["--remote-debugging-address=127.0.0.1",
                                               "--remote-debugging-port=9335",
                                               "--remote-allow-origins=http://127.0.0.1:9335"])
        print("PASS simulated restart deadlines, cancellation, replacement PIDs and page readiness")
    }
}
