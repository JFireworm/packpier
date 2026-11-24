import Darwin
import Foundation

enum SystemNode {
    static let required = "需要 Node.js 22+"

    static func candidates(home: URL, environment: [String: String]) -> [URL] {
        let override = environment["PACKPIER_NODE"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        var paths = [override].compactMap { $0 } + ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvm.path)) ?? []
        for version in versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
            paths.append(nvm.appendingPathComponent(version).appendingPathComponent("bin/node").path)
        }
        paths += [".volta/bin/node", ".local/bin/node", ".asdf/shims/node"].map { home.appendingPathComponent($0).path }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    static var environment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !["NODE_OPTIONS", "NODE_PATH"].contains($0.key) }
    }

    static func accepts(_ version: String) -> Bool {
        let parts = version.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3, parts[0].first == "v", let major = Int(parts[0].dropFirst()),
              Int(parts[1]) != nil, parts[2].first?.isNumber == true else { return false }
        return major >= 22
    }

    static func find(in paths: [URL]) -> URL? {
        for url in paths where FileManager.default.isExecutableFile(atPath: url.path) {
            let command = Process(), pipe = Pipe(), done = DispatchSemaphore(value: 0)
            command.executableURL = url
            command.arguments = ["--version"]
            command.environment = environment
            command.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            command.standardInput = FileHandle.nullDevice
            command.standardOutput = pipe
            command.standardError = FileHandle.nullDevice
            command.terminationHandler = { _ in done.signal() }
            do { try command.run() } catch { continue }
            guard done.wait(timeout: .now() + 2) == .success else {
                if command.isRunning { kill(command.processIdentifier, SIGKILL) }
                command.waitUntilExit()
                continue
            }
            guard command.terminationStatus == 0,
                  let bytes = try? pipe.fileHandleForReading.read(upToCount: 128),
                  accepts(String(decoding: bytes, as: UTF8.self)) else { continue }
            return url
        }
        return nil
    }
}
