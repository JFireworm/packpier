import Foundation

/// The manager owns this log so startup failures can be recorded before the loader replies.
struct ConnectionLog {
    let url: URL

    init(library: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]) {
        url = library.appendingPathComponent("Logs/Packpier/connection.log")
    }

    func append(_ message: String) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let line = message.components(separatedBy: .newlines).joined(separator: " ").prefix(2048)
        let entry = Data("\(Date().ISO8601Format()) \(line)\n".utf8)
        if fm.fileExists(atPath: url.path) {
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            if try file.seekToEnd() < 512 * 1024 {
                try file.write(contentsOf: entry)
                return
            }
            let previous = directory.appendingPathComponent("connection.previous.log")
            if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
            try fm.moveItem(at: url, to: previous)
        }
        guard fm.createFile(atPath: url.path, contents: entry, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}
