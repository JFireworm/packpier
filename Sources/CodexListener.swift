import AppKit
import Security

/// Verify the identity of the running process, and that its only IPv4 listener
/// on the expected port is on loopback. A bundle identifier alone is user supplied.
enum CodexListener {
    static let bundleID = "com.openai.codex"
    static func owner() -> pid_t? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        return apps.first { !$0.isTerminated && ownsEndpoint($0.processIdentifier) }?.processIdentifier
    }

    static func ownsEndpoint(_ pid: pid_t) -> Bool {
        var requirement: SecRequirement?
        let rule = "anchor apple generic and identifier \"com.openai.codex\" and certificate leaf[subject.OU] = \"2DC432GLL2\""
        var guest: SecCode?
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: pid] as CFDictionary, [], &guest) == errSecSuccess,
              let guest, let requirement, SecCodeCheckValidity(guest, [], requirement) == errSecSuccess else { return false }
        let query = Process()
        let pipe = Pipe()
        query.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        query.arguments = ["-nP","-a","-p",String(pid),"-iTCP:9335","-sTCP:LISTEN","-Fpn"]
        query.standardOutput = pipe
        query.standardError = FileHandle.nullDevice
        do { try query.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        query.waitUntilExit()
        let fields = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return query.terminationStatus == 0 && fields.contains(Substring("p\(pid)")) &&
            Set(fields.filter { $0.first == "n" }) == ["n127.0.0.1:9335"]
    }
}
