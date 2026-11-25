import AppKit

@main enum SwiftUnit {
    @MainActor static func main() async throws {
        try await CodexRestartCheck.run()
        try MarketApplicationsCheck.run()
        try WeChatOverlayCheck.run()
        try NativeUI.checkTime()
        try checkConnectionDiagnostics()
        try checkUpdateFailureLogging()
    }

    @MainActor static func checkUpdateFailureLogging() throws {
        let fm = FileManager.default
        let library = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: library) }
        let log = ConnectionLog(library: library)
        let logger = UpdateFailureLogger(log: log)
        guard logger.responds(to: NSSelectorFromString("updater:didAbortWithError:")) else {
            throw PackpierError.message("Sparkle abort selector is not exposed")
        }
        for code in [SUNoUpdateError, SUInstallationCanceledError, SUInstallationAuthorizeLaterError] {
            logger.record(NSError(domain: SUSparkleErrorDomain, code: Int(code)))
        }
        logger.record(URLError(.cancelled))
        guard !fm.fileExists(atPath: log.url.path) else {
            throw PackpierError.message("Normal Sparkle completion or cancellation was logged")
        }

        let socketError = NSError(domain: NSPOSIXErrorDomain, code: 54, userInfo: [
            NSFilePathErrorKey: "/Users/private/Downloads/update.zip"
        ])
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: [
            NSUnderlyingErrorKey: socketError,
            NSURLErrorFailingURLStringErrorKey: "https://user:pass@release-assets.githubusercontent.com:443/files/private.zip?token=secret#fragment"
        ])
        let downloadError = NSError(domain: SUSparkleErrorDomain, code: 2001, userInfo: [
            NSUnderlyingErrorKey: networkError,
            NSURLErrorFailingURLErrorKey: URL(string: "https://github.com/owner/repo")!,
            NSLocalizedDescriptionKey: "Private download location"
        ])
        let summary = "Sparkle update failed · SUSparkleErrorDomain/2001 → NSURLErrorDomain/-1005 → NSPOSIXErrorDomain/54 · host=release-assets.githubusercontent.com"
        let fileError = NSError(domain: NSCocoaErrorDomain, code: 1001, userInfo: [
            NSURLErrorFailingURLErrorKey: URL(fileURLWithPath: "/Users/private/Downloads/update.zip")
        ])
        let fileSummary = "Sparkle update failed · NSCocoaErrorDomain/1001"
        guard UpdateFailureLogger.summary(downloadError) == summary,
              UpdateFailureLogger.summary(fileError) == fileSummary else {
            throw PackpierError.message("Unexpected or unsanitized Sparkle failure summary")
        }
        logger.record(downloadError)
        logger.record(fileError)
        let lines = try String(contentsOf: log.url, encoding: .utf8).split(separator: "\n")
        guard lines.count == 2, lines[0].hasSuffix(summary), lines[1].hasSuffix(fileSummary) else {
            throw PackpierError.message("Sparkle failures did not reach the connection log")
        }
        print("PASS Sparkle abort selector, ignored normal outcomes and host-only failure log")
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
