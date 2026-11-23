import AppKit
import Security

/// Verify the identity of the running process, and that its only IPv4 listener
/// on the expected port is on loopback. A bundle identifier alone is user supplied.
enum CodexListener {
    enum Status: String {
        case available = "Codex 本机端口可连接"
        case missing = "Codex 已运行，未检测到可用的本机连接"
        case unexpectedListener = "Codex 的监听地址与本机连接要求不符"
        case identityFailed = "无法验证正在运行的 Codex 应用身份"
        case checkFailed = "未能读取 Codex 的本机连接状态"
    }
    static let bundleID = "com.openai.codex"
    static func owner() -> pid_t? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        return apps.first { !$0.isTerminated && ownsEndpoint($0.processIdentifier) }?.processIdentifier
    }

    static func ownsEndpoint(_ pid: pid_t) -> Bool {
        inspect(pid) == .available
    }

    static func inspect(_ pid: pid_t) -> Status {
        var requirement: SecRequirement?
        let rule = "anchor apple generic and identifier \"com.openai.codex\" and certificate leaf[subject.OU] = \"2DC432GLL2\""
        var guest: SecCode?
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: pid] as CFDictionary, [], &guest) == errSecSuccess,
              let guest, let requirement, SecCodeCheckValidity(guest, [], requirement) == errSecSuccess else { return .identityFailed }
        let query = Process()
        let pipe = Pipe()
        query.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        query.arguments = ["-nP","-a","-p",String(pid),"-iTCP:9335","-sTCP:LISTEN","-Fpn"]
        query.standardOutput = pipe
        query.standardError = FileHandle.nullDevice
        do { try query.run() } catch { return .checkFailed }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        query.waitUntilExit()
        return classify(String(decoding: data, as: UTF8.self), exitCode: query.terminationStatus, pid: pid)
    }

    static func classify(_ output: String, exitCode: Int32, pid: pid_t) -> Status {
        let fields = output.split(separator: "\n")
        if exitCode == 1 && fields.isEmpty { return .missing }
        guard exitCode == 0, fields.contains(Substring("p\(pid)")) else { return .checkFailed }
        let listeners = Set(fields.filter { $0.first == "n" })
        return listeners == ["n127.0.0.1:9335"] ? .available : .unexpectedListener
    }
}
