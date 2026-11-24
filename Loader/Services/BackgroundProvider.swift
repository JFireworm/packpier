import Foundation

/// Each request owns its session. Accumulate only the bounded response and handle redirects explicitly.
private final class ImageRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private var body = Data()
    private var exceeded = false
    private var continuation: CheckedContinuation<(HTTPURLResponse, Data), Error>?

    init(limit: Int) { self.limit = limit }

    func fetch(_ request: URLRequest, timeout: TimeInterval) async throws -> (HTTPURLResponse, Data) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = timeout
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        let callbacks = OperationQueue()
        callbacks.maxConcurrentOperationCount = 1
        callbacks.isSuspended = true
        let session = URLSession(configuration: config, delegate: self, delegateQueue: callbacks)
        let task = session.dataTask(with: request)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuation = $0
                task.resume()
                callbacks.isSuspended = false
            }
        } onCancel: { task.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !exceeded else { return }
        guard data.count <= limit - body.count else {
            exceeded = true
            dataTask.cancel()
            return
        }
        body.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { continuation = nil }
        if exceeded { continuation?.resume(throwing: WireError.message("图片服务响应超过大小限制")) }
        else if let error { continuation?.resume(throwing: error) }
        else if let response = task.response as? HTTPURLResponse { continuation?.resume(returning: (response, body)) }
        else { continuation?.resume(throwing: URLError(.badServerResponse)) }
    }
}

struct BackgroundProvider {
    typealias Fetch = (URLRequest, Int, TimeInterval) async throws -> (HTTPURLResponse, Data)
    private let fetch: Fetch

    init(fetch: @escaping Fetch = { request, limit, timeout in
        try await ImageRequest(limit: limit).fetch(request, timeout: timeout)
    }) { self.fetch = fetch }

    private static func host(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.port == nil || url.port == 443,
              url.user == nil, url.password == nil else { return nil }
        return url.host?.lowercased()
    }

    static func isImageURL(_ url: URL) -> Bool {
        switch host(url) {
        case "tc.alcy.cc": return true
        case "t.alcy.cc":
            return url.path.range(of: #"\A/pic/pc/[^/]+\.(webp|png|jpe?g|avif)\z"#,
                                  options: [.regularExpression, .caseInsensitive]) != nil
        default: return false
        }
    }

    func image(at url: URL) async throws -> Data {
        guard Self.isImageURL(url) else { throw WireError.message("不支持的内置图片地址") }
        let (response, data) = try await fetch(URLRequest(url: url, timeoutInterval: 15), BackgroundService.maxBytes, 15)
        guard (200..<300).contains(response.statusCode), data.count <= BackgroundService.maxBytes else {
            throw WireError.message("获取内置图片失败")
        }
        return data
    }

    func lookup(url: URL, method: String, responseType: String, timeoutMs: Double = 10000) async throws -> JSONObject {
        guard Self.host(url) == "t.alcy.cc",
              (url.path == "/pc" && method == "HEAD" && responseType == "none") ||
              (url.path == "/json" && method == "GET" && responseType == "json") else {
            throw WireError.message("不支持的内置图片查询")
        }
        let timeout = min(60000, max(1, timeoutMs == 0 || !timeoutMs.isFinite ? 10000 : timeoutMs)) / 1000
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var target = url
        for hop in 0...3 {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw URLError(.timedOut) }
            var request = URLRequest(url: target, timeoutInterval: remaining)
            request.httpMethod = method
            request.setValue("Packpier/custom-background", forHTTPHeaderField: "User-Agent")
            let (response, data) = try await fetch(request, 65536, remaining)
            let status = response.statusCode
            if (300..<400).contains(status) {
                guard hop < 3, method == "HEAD", let location = response.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: target)?.absoluteURL, Self.isImageURL(next) else {
                    throw WireError.message("图片服务返回了不支持的重定向")
                }
                target = next
                continue
            }
            let ok = (200..<300).contains(status)
            var body: Any = NSNull()
            if ok && responseType == "json" {
                guard data.count <= 65536 else { throw WireError.message("图片服务响应超过大小限制") }
                body = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            }
            return ["ok": ok, "status": status, "finalUrl": target.absoluteString,
                    "contentType": response.value(forHTTPHeaderField: "Content-Type") ?? "", "body": body]
        }
        throw WireError.message("图片服务重定向次数过多")
    }
}
