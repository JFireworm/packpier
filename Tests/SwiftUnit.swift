import AppKit

@main enum SwiftUnit {
    @MainActor static func main() async throws {
        try MarketApplicationsCheck.run()
        try WeChatOverlayCheck.run()
        try NativeUI.checkTime()
        try checkConnectionDiagnostics()
        try await CodexRestartCheck.run()
    }

    @MainActor static func checkConnectionDiagnostics() throws {
        let fm = FileManager.default
        let library = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: library) }
        let log = ConnectionLog(library: library)
        let manager = Manager(connectionLog: log)
        let file = try manager.logFileForReveal()
        guard file == library.appendingPathComponent("Logs/Packpier/connection.log"),
              try String(contentsOf: file, encoding: .utf8).contains("loaderResponded=false") else {
            throw PackpierError.message("First launch did not create a diagnostic log before the loader replied")
        }
        manager.state = HostState(raw: ["packages": [], "status": ["kind":"waitingForCDP"]])
        _ = try manager.logFileForReveal()
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        guard lines.count == 2, lines.last?.contains("loaderResponded=true window=waitingForCDP") == true else {
            throw PackpierError.message("The latest connection state did not reach the revealed log")
        }
        let pid: pid_t = 123
        manager.connection = CodexListener.Status.missing.rawValue
        manager.state = HostState(raw: ["enabled":true, "packages":[], "status":["kind":"waitingForCDP"]])
        guard manager.canRestartCodex else { throw PackpierError.message("Missing inline restart action") }
        manager.connection = CodexListener.Status.identityFailed.rawValue
        guard !manager.canRestartCodex else { throw PackpierError.message("Offered to restart an unverified application") }
        manager.connection = CodexListener.Status.missing.rawValue
        manager.state = HostState(raw: ["enabled":true, "packages":[], "status":["kind":"connected"]])
        guard !manager.canRestartCodex else { throw PackpierError.message("Connected window offered restart") }
        guard CodexListener.classify("", exitCode: 1, pid: pid) == .missing,
              CodexListener.classify("", exitCode: 2, pid: pid) == .checkFailed,
              CodexListener.classify("p456\nn127.0.0.1:9335", exitCode: 0, pid: pid) == .checkFailed,
              CodexListener.classify("p123\nn*:9335", exitCode: 0, pid: pid) == .unexpectedListener,
              CodexListener.classify("p123\nn127.0.0.1:9335\nn*:9335", exitCode: 0, pid: pid) == .unexpectedListener,
              CodexListener.classify("p123\nn127.0.0.1:9335", exitCode: 0, pid: pid) == .available else {
            throw PackpierError.message("Expected distinct listener diagnostics")
        }
        print("PASS fresh-install log creation, before/after loader reply and listener diagnostics")
    }
}
