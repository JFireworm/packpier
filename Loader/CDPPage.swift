import Foundation

/// One Chrome DevTools Protocol page session. The loader talks to Codex's own
/// loopback DevTools endpoint; there is no external runtime involved.
final class CDPPage {
    let targetID: String
    private let url: URL
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private let lock = NSLock()
    private var sequence = 0
    private var pending: [Int: (Result<JSONObject, Error>) -> Void] = [:]
    private var closed = false
    private var closing = false

    var onBinding: ((JSONObject) -> Void)?
    var onClose: (() -> Void)?
    private(set) var confirmed = false

    init(targetID: String, url: URL) {
        self.targetID = targetID
        self.url = url
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    deinit { session.invalidateAndCancel() }

    func open() async throws {
        let task = session.webSocketTask(with: url)
        lock.lock()
        socket = task
        lock.unlock()
        task.resume()
        receive()
        _ = try await send("Runtime.enable", [:], timeout: 6)
        lock.lock()
        confirmed = !closed
        lock.unlock()
        guard confirmed else { throw WireError.message("Codex page closed during handshake") }
    }

    func evaluate(_ expression: String, timeout: TimeInterval = 20) async throws -> Any? {
        let reply = try await send("Runtime.evaluate",
                                   ["expression": expression, "returnByValue": true, "awaitPromise": true],
                                   timeout: timeout)
        if let exception = reply["exceptionDetails"] as? JSONObject {
            let text = jsonString(exception["text"]) ?? "JavaScript exception"
            throw WireError.message(text)
        }
        return jsonObject(reply["result"])?["value"]
    }

    func send(_ method: String, _ params: JSONObject = [:], timeout: TimeInterval = 15) async throws -> JSONObject {
        let id: Int = {
            lock.lock()
            defer { lock.unlock() }
            sequence += 1
            return sequence
        }()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if closed {
                lock.unlock()
                continuation.resume(throwing: WireError.message("Codex page closed"))
                return
            }
            pending[id] = { result in continuation.resume(with: result) }
            lock.unlock()

            let payload: JSONObject = ["id": id, "method": method, "params": params]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: data, encoding: .utf8) else {
                fail(id, WireError.message("Cannot encode CDP request"))
                return
            }
            socket?.send(.string(text)) { [weak self] error in
                if let error { self?.fail(id, error) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.fail(id, WireError.message("CDP \(method) timed out"))
            }
        }
    }

    func close() {
        lock.lock()
        if closing { lock.unlock(); return }
        closing = true
        let task = socket
        lock.unlock()
        task?.cancel(with: .normalClosure, reason: nil)
        finish(WireError.message("Codex page closed"))
    }

    private func receive() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(error)
            case .success(let message):
                switch message {
                case .string(let text): self.handle(text)
                case .data(let data): self.handle(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
                self.receive()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? JSONObject else { return }
        if let id = jsonInt(message["id"]) {
            resolve(id, .success(jsonObject(message["result"]) ?? [:]))
            return
        }
        if jsonString(message["method"]) == "Runtime.bindingCalled",
           let params = jsonObject(message["params"]),
           jsonString(params["name"]) == "__packpierRpc",
           let payload = jsonString(params["payload"]),
           let payloadData = payload.data(using: .utf8),
           let request = try? JSONSerialization.jsonObject(with: payloadData) as? JSONObject {
            onBinding?(request)
        }
    }

    private func resolve(_ id: Int, _ result: Result<JSONObject, Error>) {
        lock.lock()
        let completion = pending.removeValue(forKey: id)
        lock.unlock()
        completion?(result)
    }

    private func fail(_ id: Int, _ error: Error) {
        resolve(id, .failure(error))
    }

    private func finish(_ error: Error) {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        closed = true
        let waiting = pending
        pending.removeAll()
        lock.unlock()
        for completion in waiting.values { completion(.failure(error)) }
        onClose?()
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }
}