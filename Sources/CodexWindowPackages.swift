import Foundation

/// Read the mounted package IDs in the same local Codex windows used by the adapter.
/// A completed runtime is published only after package activation and cleanup of failed roots.
enum CodexWindowPackages {
    private struct Page: Decodable { let type, url: String; let webSocketDebuggerUrl: URL? }
    private static let port = 9335
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 4
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.connectionProxyDictionary = [:]
        return URLSession(configuration:config)
    }()
    static func read() async -> Set<String> {
        guard let (data, _) = try? await session.data(from:URL(string:"http://127.0.0.1:9335/json/list")!),
              let pages = try? JSONDecoder().decode([Page].self,from:data) else { return [] }
        return await withTaskGroup(of:Set<String>.self) { group in
            for page in pages where page.type == "page" {
                guard let app = URLComponents(string:page.url), app.scheme == "app", app.host == "-", app.path == "/index.html",
                      !page.url.contains("avatar-overlay"), let socket = page.webSocketDebuggerUrl,
                      socket.scheme == "ws", socket.host == "127.0.0.1", socket.port == port,
                      socket.path.hasPrefix("/devtools/page/"), socket.user == nil, socket.password == nil else { continue }
                group.addTask { await mounted(in:socket) }
            }
            var ids = Set<String>()
            for await oneWindow in group { ids.formUnion(oneWindow) }
            return ids
        }
    }
    private static func mounted(in url:URL) async -> Set<String> {
        let socket = session.webSocketTask(with:url)
        let deadline = Task {
            try await Task.sleep(for:.seconds(3))
            socket.cancel()
        }
        defer { deadline.cancel(); socket.cancel() }
        socket.resume()
        let expression = """
        globalThis.__PACKPIER__?.version
          ? Array.from(document.querySelectorAll('[data-packpier-plugin]'),
                       node => node.getAttribute('data-packpier-plugin')) : []
        """
        do {
            let command: Fields = ["id":1,"method":"Runtime.evaluate","params":["expression":expression,"returnByValue":true]]
            let data = try JSONSerialization.data(withJSONObject:command)
            try await socket.send(.string(String(decoding:data,as:UTF8.self)))
            guard case .string(let text) = try await socket.receive(),
                  let reply = try JSONSerialization.jsonObject(with:Data(text.utf8)) as? Fields,
                  let result = reply["result"] as? Fields, let value = result["result"] as? Fields,
                  let ids = value["value"] as? [String] else { return [] }
            return Set(ids)
        } catch { return [] }
    }
}
