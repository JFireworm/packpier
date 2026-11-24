import AppKit
import ImageIO
import SQLite3

@main struct NativeServiceTests {
    static func check(_ matches: Bool, _ reason: String) throws {
        guard matches else { throw WireError.message(reason) }
    }

    static func rejected(_ operation: () async throws -> Void) async throws {
        do { try await operation() } catch { return }
        throw WireError.message("Expected the operation to fail")
    }

    static func database(_ url: URL, sql: String) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(url.path, &db) == SQLITE_OK,
              sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw WireError.message("Invalid fixture database") }
    }

    static func testPrism(_ home: URL) async throws {
        let root = home.appendingPathComponent("codex")
        let data = home.appendingPathComponent("library/node-data/2f4e9f248cb97922")
        let settings = home.appendingPathComponent("library/app-state.json")
        let preferences = data.appendingPathComponent("preferences-account_1.json")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sqlite"), withIntermediateDirectories: true)
        let catalog = root.appendingPathComponent("sqlite/codex.db")
        let legacy = root.appendingPathComponent("state_5.sqlite")
        try database(catalog, sql: """
            CREATE TABLE local_thread_catalog(thread_id,host_id,display_title,cwd,project_id);
            INSERT INTO local_thread_catalog VALUES ('one','local','First','/a','native-a');
            INSERT INTO local_thread_catalog VALUES ('01a202f7','local','Flying chat','/b','d0b14761');
            """)
        try database(legacy, sql: """
            CREATE TABLE threads(id,name,cwd,archived);
            INSERT INTO threads VALUES ('old','Legacy','/b',0), ('archived','Archived','/b',1);
            """)
        let inputs = try [catalog, legacy].map { try Data(contentsOf: $0) }
        let atoms: JSONObject = ["app-server-pinned-thread-order-v1": ["one", "missing", "old", "one", "archived"],
                                 "unified-sidebar-project-order-v1": ["codex:project:b", "codex:project:a"]]
        let stateFile = root.appendingPathComponent(".codex-global-state.json")
        var global: JSONObject = ["electron-owner-atoms:account_1": atoms, "electron-owner-atoms:other": atoms,
                                  "electron-renderer-content-owner": "account_1",
                                  "sidebar-custom-sections-v3": [
                                    "account_1": [["id": "flying", "name": "Flying",
                                                   "itemKeys": ["codex:thread:local:01a202f7", "codex:project:d0b14761"]]],
                                    "other": [["id": "private", "name": "Other account", "itemKeys": ["codex:project:missing"]]],
                                  ],
                                  "local-projects": ["a": ["rootPaths": ["/a"]], "b": ["rootPaths": ["/b"]]],
                                  "app-server-project-id-by-legacy-project-id-by-host": ["local": ["a": "native-a"]]]
        try writeJSONObject(global, to: stateFile)
        try writeJSONObject(["language": "ja"], to: settings)
        let service = PrismService(codexRoot: root, dataDirectory: data)
        let snap = try await service.snapshot()
        let rows = snap["threads"] as? [JSONObject] ?? []
        try check(rows.compactMap { $0["nativeIndex"] as? Int } == [1, 3], "Pinned order or archived filtering changed")
        try check(rows.compactMap { $0["projectId"] as? String } == ["a", "b"], "Legacy project mapping changed")
        try check(!FileManager.default.fileExists(atPath: preferences.path), "Snapshot wrote the preference file")
        try check(snap["language"] as? String == "ja", "Language was not read from app-state.json")
        let _ = try await service.update(account: "account_1", operation: ["type": "color", "key": "project:a",
                                                                            "value": "#acdbfe", "inherit": true])
        var prefs = try readJSONObject(preferences)
        prefs["groups"] = [["id": "existing", "name": "Group"]]
        prefs["futureField"] = "keep"
        try writeJSONObject(prefs, to: preferences)
        let sections = snap["customSections"] as? [JSONObject] ?? []
        let threadKey = "codex:thread:local:01a202f7"
        try check(sections.count == 1 && sections.first?["name"] as? String == "Flying" &&
                  sections.first?["threadKeys"] as? [String] == [threadKey] &&
                  sections.first?["projectKeys"] as? [String] == ["codex:project:d0b14761"], "Wrong account's custom sections")
        let custom = (snap["customThreads"] as? [JSONObject])?.first
        try check(custom?["title"] as? String == "Flying chat" && custom?["projectId"] as? String == "d0b14761",
                  "Missing unpinned thread metadata")
        _ = try await service.update(account: "account_1", operation: ["type": "color",
            "key": "project:d0b14761", "value": "#118ACC"])
        let edited = try await service.update(account: "account_1", operation: ["type": "color",
            "key": threadKey, "source": "project", "value": NSNull()])
        try check((edited["threadProjects"] as? JSONObject)?[threadKey] as? String == "d0b14761", "Unpinned inheritance lost")
        _ = try await service.update(account: "account_1", operation: ["type": "color", "key": threadKey, "value": "#408A70"])
        let reopened = try await PrismService(codexRoot: root, dataDirectory: data).snapshot()
        let restored = (reopened["preferences"] as? JSONObject)?["colors"] as? [String: String]
        try check(restored?[threadKey] == "#408A70" && restored?["project:d0b14761"] == "#118ACC", "Custom colors did not persist")
        async let first = service.update(account: "account_1", operation: ["type": "preset-color", "slot": 0, "value": "#abcdef"])
        async let second = service.update(account: "account_1", operation: ["type": "mode", "value": "project"])
        _ = try await (first, second)
        let result = try readJSONObject(preferences)
        try check(result["futureField"] as? String == "keep" && result["mode"] as? String == "project", "Lost preferences")
        try check((result["groups"] as? [[String: String]])?.first?["id"] == "existing", "Lost group")
        try check((result["colors"] as? [String: String])?["project:a"] == "#ACDBFE", "Lost project color")
        try check((result["presetColors"] as? [String])?.first == "#ABCDEF", "Lost preset")
        let before = try Data(contentsOf: preferences)
        try await rejected { _ = try await service.update(account: "other", operation: ["type": "mode", "value": "all"]) }
        try await rejected { _ = try await service.update(account: "account_1", operation: ["type": "color", "key": "project:missing", "value": NSNull()]) }
        global["electron-renderer-content-owner"] = "unknown"
        try writeJSONObject(global, to: stateFile)
        try await rejected { _ = try await service.snapshot() }
        try check(try Data(contentsOf: preferences) == before, "Rejected edit wrote settings")
        try check(try [catalog, legacy].map { try Data(contentsOf: $0) } == inputs, "A Codex database changed")
        try check(PrismService.language("auto", preferred: ["fr", "zh_Hant_HK"]) == "zh-TW", "System language mismatch")
    }

    static func testImages(_ home: URL) async throws {
        // A one-pixel fixture exercises the native decoder and both clipboard encoders.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)
        guard let tiff = bitmap?.tiffRepresentation else { throw WireError.message("Missing TIFF fixture") }
        let images = try BackgroundService.clipboardImages(tiff)
        for (type, signature) in [(NSPasteboard.PasteboardType.png, "png"), (.tiff, "tif")] {
            guard let bytes = images[type] else { throw WireError.message("Missing clipboard representation") }
            try check(try BackgroundService.imageExtension(bytes) == signature, "Incorrect clipboard image format")
            let source = CGImageSourceCreateWithData(bytes as CFData, nil)
            try check(source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.width == 1, "Invalid clipboard image")
        }
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10]) + Data(repeating: 42, count: BackgroundService.chunkSize)
        let service = BackgroundService(home: home)
        func favorite() async throws -> String {
            let id = UUID().uuidString.lowercased()
            let first = png.prefix(BackgroundService.chunkSize)
            try await service.upload(id: id, offset: 0, base64: first.base64EncodedString())
            try await rejected { try await service.upload(id: id, offset: 2, base64: "YQ==") }
            try await service.upload(id: id, offset: first.count, base64: png.dropFirst(first.count).base64EncodedString())
            let result = try await service.action("favorite", upload: id)
            guard let file = result["file"] as? String else { throw WireError.message("Missing filename") }
            return file
        }
        let file = try await favorite()
        try check(try await favorite() == file, "Duplicate favorite")
        let saved = home.appendingPathComponent("Pictures/Packpier/收藏/" + file)
        try check(try Data(contentsOf: saved) == png, "Favorite bytes changed")
        let chunk = try await service.read(file: file, offset: BackgroundService.chunkSize)
        try check(chunk["data"] as? String == png.suffix(8).base64EncodedString(), "Final chunk mismatch")
        try await rejected { _ = try await service.read(file: "../elsewhere", offset: 0) }
        try await rejected { _ = try await service.read(file: file, offset: png.count) }
        let name = try await service.action("save", file: file)["file"] as? String
        let url = home.appendingPathComponent("Downloads").appendingPathComponent(name ?? "")
        try check(try Data(contentsOf: url) == png, "Download bytes changed")
        try FileManager.default.removeItem(at: saved)
        try check(try await service.action("save", file: file)["missing"] as? Bool == true, "Missing favorite not reported")
        try FileManager.default.createSymbolicLink(at: saved, withDestinationURL: url)
        try await rejected { _ = try await service.read(file: file, offset: 0) }
    }

    static func testProvider() async throws {
        let endpoint = URL(string: "https://t.alcy.cc/pc")!
        let fixture = BackgroundProvider { request, _, _ in
            guard let url = request.url else { throw URLError(.badURL) }
            let redirect = url == endpoint
            let response = HTTPURLResponse(url: url, statusCode: redirect ? 302 : 200, httpVersion: nil,
                                           headerFields: redirect ? ["Location": "/pic/pc/demo.webp"] : ["Content-Type": "image/webp"])!
            return (response, Data())
        }
        let result = try await fixture.lookup(url: endpoint, method: "HEAD", responseType: "none")
        try check(result["finalUrl"] as? String == "https://t.alcy.cc/pic/pc/demo.webp", "Image lookup redirect mismatch")
        let forbidden = BackgroundProvider { request, _, _ in
            (HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://example.com/file"])!, Data())
        }
        try await rejected { _ = try await forbidden.lookup(url: endpoint, method: "HEAD", responseType: "none") }
        try await rejected { _ = try await fixture.image(at: URL(string: "https://example.com/test.png")!) }
        try await rejected { _ = try await fixture.lookup(url: endpoint, method: "GET", responseType: "json") }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try await testPrism(root)
        try await testImages(root)
        try await testProvider()
        print("PASS native Prism snapshots and edits, favorite transfers and provider lookup (isolated fixtures)")
    }
}
