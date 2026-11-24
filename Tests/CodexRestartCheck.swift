import Foundation

@MainActor enum CodexRestartCheck {
    private enum Scenario { case success, forced, timeout, replacement, missingPort, missingPage, pidChanged, cancelled }

    static func run() async throws {
        for scenario: Scenario in [.success, .forced, .timeout, .replacement, .missingPort, .missingPage, .pidChanged, .cancelled] {
            var time = 0.0
            var opens = 0
            var reads = 0
            var messages: [String] = []
            var forced = 0
            let flow = CodexRestart(requestQuit: { true },
                runningPIDs: {
                    if opens == 0 {
                        if scenario == .replacement && time >= 0.5 { return [222] }
                        if scenario == .timeout || time < (scenario == .forced ? 6 : 1) { return [101] }
                        return []
                    }
                    return scenario == .pidChanged && reads > 0 ? [333] : [111]
                }, open: { opens += 1; return 111 }, endpointReady: { _ in scenario != .missingPort }, ready: { pid in
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
                precondition(messages == ["正在等待 Codex 退出…", "正在启动 Codex", "正在等待 Codex 连接端口…", "正在连接 Codex 窗口…"])
            case .forced:
                precondition(failure == nil && forced == 1 && opens == 1 && time >= 6)
            case .timeout:
                precondition(failure?.localizedDescription == "Codex 未能正常退出，请手动退出后重试。" && opens == 0)
                precondition(time == 8 && forced == 1)
            case .replacement, .pidChanged:
                precondition(failure?.localizedDescription == "Codex 运行状态已变化，请查看连接详情。")
                precondition(opens == (scenario == .replacement ? 0 : 1))
            case .missingPage:
                precondition(failure?.localizedDescription == "Codex 已重新打开，窗口仍未连接。" && time == 21 && opens == 1)
            case .missingPort:
                precondition(failure?.localizedDescription == "Codex 已重新打开，连接端口尚未就绪。" && time == 21 && reads == 0)
            case .cancelled:
                precondition(failure is CancellationError && opens == 0)
            }
        }
        await monitorDoesNotRaceRestart()
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
        print("PASS simulated restart deadlines, cancellation, replacement PIDs, monitor pause and page readiness")
    }

    private static func monitorDoesNotRaceRestart() async {
        let startup = CodexStartup()
        var oldProbe: CheckedContinuation<String?, Never>?
        var launches = 0
        var reports: [String] = []
        let launch: @MainActor () async -> String = { launches += 1; return "launched" }
        startup.start(sample: {
            await withCheckedContinuation { oldProbe = $0 }
        }, launch: launch, report: { reports.append($0) })
        while oldProbe == nil { await Task.yield() }
        startup.pauseForRestart()
        startup.start(sample: { preconditionFailure("Restart monitor not paused") }, launch: launch,
                      report: { reports.append($0) })
        oldProbe?.resume(returning: nil)
        // Model either restart outcome. The monitor can observe but cannot auto-launch again.
        startup.resumeAfterRestart()
        startup.start(sample: { nil }, launch: launch, report: { reports.append($0) })
        while reports.isEmpty { await Task.yield() }
        startup.stop()
        precondition(launches == 0 && reports == ["Codex 未运行"])
    }
}
