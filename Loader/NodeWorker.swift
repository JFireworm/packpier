import Darwin
import Foundation

enum NodeTransportError: LocalizedError {
    case stopped, timedOut
    var errorDescription: String? {
        self == .stopped ? "Node plugin has stopped" : "Node plugin response timed out"
    }
}

/// One private stdio connection per approved package. The loader serializes callers.
final class NodeWorker {
    private let process = Process()
    private let input = Pipe()
    private let lock = NSCondition()
    private let writes = DispatchQueue(label: "packpier.node.input")
    private var nextID = 0
    private var pendingID: Int?
    private var reply: Object?
    private var ended = false
    var running: Bool { process.isRunning }

    init(executable: URL, runner: URL, source: NodeSource, data: URL, onExit: @escaping () -> Void,
         event: @escaping (String, Any) -> Void) throws {
        let output = Pipe()
        process.executableURL = executable
        process.arguments = [runner.path]
        process.currentDirectoryURL = source.folder
        process.environment = SystemNode.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in DispatchQueue.global(qos: .utility).async { onExit() } }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let reader = output.fileHandleForReading
            var buffer = Data()
            defer {
                try? reader.close()
                self?.finish()
            }
            var chunk = [UInt8](repeating: 0, count: 16_384)
            while true {
                let count = chunk.withUnsafeMutableBytes { Darwin.read(reader.fileDescriptor, $0.baseAddress, $0.count) }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return }
                buffer.append(contentsOf: chunk.prefix(count))
                while let newline = buffer.firstIndex(of: 10) {
                    let row = buffer[..<newline]
                    guard row.count <= 1_048_576, let msg = try? JSONSerialization.jsonObject(with: row) as? Object else { return }
                    buffer.removeSubrange(...newline)
                    if msg["type"] as? String == "event", let name = msg["name"] as? String {
                        event(name, msg["payload"] ?? NSNull())
                    } else if msg["type"] as? String == "result" {
                        self?.receive(msg)
                    }
                }
                if buffer.count > 1_048_576 { return }
            }
        }
        do {
            _ = try request(["type": "init", "entry": source.entry.path, "dataDirectory": data.path])
        } catch {
            stop()
            throw error
        }
    }

    private func finish() {
        lock.lock()
        ended = true
        lock.broadcast()
        lock.unlock()
    }

    private func receive(_ result: Object) {
        lock.lock()
        defer { lock.unlock() }
        guard let pendingID, result["id"] as? Int == pendingID else { return }
        reply = result
        lock.broadcast()
    }

    func request(_ object: Object) throws -> Any {
        lock.lock()
        defer { pendingID = nil; reply = nil; lock.unlock() }
        guard !ended && running else { throw NodeTransportError.stopped }
        nextID += 1
        pendingID = nextID
        var message = object
        message["id"] = nextID
        var bytes = try JSONSerialization.data(withJSONObject: message)
        guard bytes.count <= 1_048_576 else { throw LibraryError("Node request is too large") }
        bytes.append(10)
        let line = bytes
        writes.async { [weak self, input] in
            do { try input.fileHandleForWriting.write(contentsOf: line) } catch { self?.finish() }
        }
        let deadline = Date(timeIntervalSinceNow: 5)
        while reply == nil && !ended && lock.wait(until: deadline) {}
        guard let reply else { throw ended ? NodeTransportError.stopped : NodeTransportError.timedOut }
        guard reply["ok"] as? Bool == true else { throw LibraryError(reply["error"] as? String ?? "Node plugin error") }
        return reply["value"] ?? NSNull()
    }

    func stop() {
        try? input.fileHandleForWriting.close()
        // EOF lets a well-behaved plugin run its cleanup. Bound shutdown of our own child.
        for _ in 0..<20 where process.isRunning { Thread.sleep(forTimeInterval: 0.025) }
        if process.isRunning { process.terminate() }
        for _ in 0..<10 where process.isRunning { Thread.sleep(forTimeInterval: 0.025) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}
