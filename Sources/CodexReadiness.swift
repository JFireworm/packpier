import Foundation

/// A read-only health check. It never follows a redirect or opens a page socket.
enum CodexReadiness {
    private static let endpoint = URL(string: "http://127.0.0.1:9335/json/list")!

    private final class LocalOnly: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let client: URLSession = {
        let settings = URLSessionConfiguration.ephemeral
        settings.connectionProxyDictionary = [:]
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.urlCache = nil
        settings.timeoutIntervalForResource = 1
        return URLSession(configuration: settings, delegate: LocalOnly(), delegateQueue: nil)
    }()

    static func hasMainPage(_ data: Data) -> Bool {
        guard let targets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
        return targets.contains { page in
            guard page["type"] as? String == "page", let address = page["url"] as? String,
                  let url = URLComponents(string: address),
                  url.scheme == "app", url.host == "-", url.port == nil, url.user == nil, url.password == nil,
                  url.percentEncodedPath == "/index.html", let decoded = address.removingPercentEncoding else { return false }
            return !decoded.localizedCaseInsensitiveContains("avatar-overlay")
        }
    }

    static func ready(pid: pid_t) async -> Bool {
        guard !Task.isCancelled, CodexListener.inspect(pid) == .available else { return false }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await client.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == endpoint,
                  http.expectedContentLength <= 524_288 else { return false }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 524_288 else { return false }
                data.append(byte)
            }
            return !Task.isCancelled && hasMainPage(data) && CodexListener.inspect(pid) == .available
        } catch { return false }
    }
}
