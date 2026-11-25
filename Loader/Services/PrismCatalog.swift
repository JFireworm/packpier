import Foundation
import SQLite3

/// One prepared, read-only lookup per database for the lifetime of a snapshot.
private final class ThreadLookup {
    private let database: OpaquePointer
    private let statement: OpaquePointer

    init(_ url: URL, sql: String) throws {
        var db: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw WireError.message("无法读取 " + url.lastPathComponent)
        }
        sqlite3_busy_timeout(db, 1000)
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else {
            let error = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw WireError.message(error)
        }
        database = db
        statement = prepared
    }

    deinit {
        sqlite3_finalize(statement)
        sqlite3_close(database)
    }

    func row(_ id: String) throws -> [String: String]? {
        sqlite3_reset(statement)
        guard sqlite3_bind_text(statement, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else {
            throw WireError.message(String(cString: sqlite3_errmsg(database)))
        }
        switch sqlite3_step(statement) {
        case SQLITE_DONE: return nil
        case SQLITE_ROW:
            var fields: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                if let string = sqlite3_column_text(statement, column) {
                    fields[String(cString: sqlite3_column_name(statement, column))] = String(cString: string)
                }
            }
            return fields
        default: throw WireError.message(String(cString: sqlite3_errmsg(database)))
        }
    }
}

struct PrismCatalog {
    static let threadPrefix = "codex:thread:local:"
    static let clientThreadPrefix = "client-new-thread:"
    static let projectPrefix = "codex:project:"
    let account: String
    let projects: [[String: String]]
    let aliases: [String: String]
    private let pins: [String]
    private let clientBindings: [String: String]
    private let assignments: [String: [String: String]]
    private let customSections: [CustomSection]
    private let catalog: ThreadLookup
    private let legacy: ThreadLookup

    private struct CustomSection {
        let id: String
        let name: String
        let threadKeys: [String]
        let projectKeys: [String]

        var json: JSONObject { ["id": id, "name": name, "threadKeys": threadKeys, "projectKeys": projectKeys] }
    }

    init(root: URL) throws {
        let state = try readJSONObject(root.appendingPathComponent(".codex-global-state.json"))
        let prefix = "electron-owner-atoms:"
        let owners = state.keys.filter { $0.hasPrefix(prefix) }
        let selected = (state["electron-renderer-content-owner"] as? String).map { prefix + $0 }
        guard let owner = selected ?? (owners.count == 1 ? owners.first : nil),
              let atoms = state[owner] as? JSONObject else {
            throw WireError.message("无法确定当前 Codex 账户")
        }
        let currentAccount = String(owner.dropFirst(prefix.count))
        guard currentAccount.range(of: #"\A[a-zA-Z0-9_-]{1,128}\z"#, options: .regularExpression) != nil else {
            throw WireError.message("无效账户标识")
        }
        account = currentAccount
        guard let pinned = atoms["app-server-pinned-thread-order-v1"] as? [String] else {
            throw WireError.message("当前 Codex 置顶数据格式不受支持")
        }
        let clientPrefix = Self.clientThreadPrefix
        let bindings = (atoms["client-thread-bindings-v1"] as? JSONObject ?? [:])
            .filter { $0.key.hasPrefix(clientPrefix) && $0.key.count > clientPrefix.count }
            .compactMapValues { ($0 as? String).flatMap { $0.isEmpty ? nil : $0 } }
        clientBindings = bindings
        var seen: Set<String> = []
        pins = pinned.map { bindings[$0] ?? $0 }.filter { seen.insert($0).inserted }
        let assignmentObjects = state["thread-project-assignments"] as? [String: JSONObject] ?? [:]
        assignments = assignmentObjects.mapValues { $0.compactMapValues { $0 as? String } }
        let raw = state["local-projects"] as? [String: JSONObject] ?? [:]
        let appearances = state["project-appearances"] as? [String: JSONObject] ?? [:]
        let order = atoms["unified-sidebar-project-order-v1"] as? [String] ?? []
        let ids = raw.keys.sorted { a, b in
            let left = order.firstIndex(of: "codex:project:" + a) ?? Int.max
            let right = order.firstIndex(of: "codex:project:" + b) ?? Int.max
            return left == right ? a < b : left < right
        }
        projects = ids.map { id in
            let name = appearances[id]?["name"] as? String ?? ""
            let original = raw[id]?["name"] as? String ?? ""
            return ["id": id, "name": name.isEmpty ? (original.isEmpty ? id : original) : name,
                    "path": (raw[id]?["rootPaths"] as? [String])?.first ?? ""]
        }
        var aliases: [String: String] = [:]
        let mappings = state["app-server-project-id-by-legacy-project-id-by-host"] as? [String: [String: String]] ?? [:]
        for mapping in mappings.values {
            for (old, native) in mapping { aliases[native] = old }
        }
        self.aliases = aliases
        let sectionKey = "sidebar-custom-sections-v3"
        // Some builds place the account map inside the owner atom store.
        let persisted = state["electron-persisted-atom-state"] as? JSONObject
        let scoped = [atoms[sectionKey], state[sectionKey], persisted?[sectionKey]]
            .lazy.compactMap { ($0 as? JSONObject)?[currentAccount] }.first
        let rawSections = scoped as? [JSONObject]
            ?? (scoped as? JSONObject)?["sections"] as? [JSONObject]
            ?? atoms[sectionKey] as? [JSONObject] ?? []
        customSections = rawSections.compactMap { section in
            guard let id = section["id"] as? String, !id.isEmpty,
                  let name = (section["name"] ?? section["title"]) as? String,
                  let items = section["itemKeys"] as? [String] else { return nil }
            var seenThreads: Set<String> = []
            let threadKeys = items.compactMap { item -> String? in
                guard item.hasPrefix(Self.threadPrefix), item.count > Self.threadPrefix.count else { return nil }
                let id = String(item.dropFirst(Self.threadPrefix.count))
                let key = Self.threadPrefix + (bindings[id] ?? id)
                return seenThreads.insert(key).inserted ? key : nil
            }
            let projectKeys = items.compactMap { item -> String? in
                guard item.hasPrefix(Self.projectPrefix) else { return nil }
                let id = String(item.dropFirst(Self.projectPrefix.count))
                return id.isEmpty ? nil : Self.projectPrefix + (aliases[id] ?? id)
            }
            return CustomSection(id: id, name: name, threadKeys: threadKeys, projectKeys: projectKeys)
        }
        catalog = try ThreadLookup(root.appendingPathComponent("sqlite/codex.db"), sql:
            "SELECT display_title, cwd, project_id FROM local_thread_catalog WHERE thread_id=? AND host_id='local'")
        legacy = try ThreadLookup(root.appendingPathComponent("state_5.sqlite"), sql:
            "SELECT name, cwd, archived FROM threads WHERE id=?")
    }

    private func project(id: String, row: [String: String]?, fallback: [String: String]?) -> String? {
        if let assigned = assignments[id]?["projectId"], !assigned.isEmpty { return aliases[assigned] ?? assigned }
        if let native = row?["project_id"], !native.isEmpty { return aliases[native] ?? native }
        let cwd = row?["cwd"].flatMap { $0.isEmpty ? nil : $0 } ?? fallback?["cwd"]
        return projects.first(where: { $0["path"] == cwd })?["id"]
    }

    func sidebar(inherited: Set<String>, editing: String?) throws -> (state: JSONObject, editable: Set<String>) {
        var threads: [JSONObject] = []
        var customThreads: [JSONObject] = []
        var locations: JSONObject = [:]
        var editable = Set(projects.compactMap { $0["id"].map { "project:" + $0 } })
        let sectionThreads = Set(customSections.flatMap(\.threadKeys))
        for key in customSections.flatMap(\.projectKeys) { editable.insert(String(key.dropFirst("codex:".count))) }
        for (index, id) in pins.enumerated() {
            let row = try catalog.row(id)
            let old = try legacy.row(id)
            guard (Int(old?["archived"] ?? "") ?? 0) == 0 else { continue }
            let hasTitle = !(row?["display_title"] ?? "").isEmpty || !(old?["name"] ?? "").isEmpty
            let key = Self.threadPrefix + id
            let location: Any = project(id: id, row: row, fallback: old) as Any? ?? NSNull()
            var thread: JSONObject = ["id": id, "kind": "codex", "hostId": "local", "projectId": location, "nativeIndex": index + 1]
            if !hasTitle { thread["pending"] = true }
            threads.append(thread)
            locations[key] = location
            editable.insert(key)
        }
        let detailKeys = sectionThreads.union(inherited).union(editing.map { [$0] } ?? [])
        for key in detailKeys.sorted() where key.hasPrefix(Self.threadPrefix) {
            let id = String(key.dropFirst(Self.threadPrefix.count))
            guard !id.isEmpty, locations[key] == nil || sectionThreads.contains(key) else { continue }
            let row = try catalog.row(id)
            let old = try legacy.row(id)
            let archived = (Int(old?["archived"] ?? "") ?? 0) != 0
            let inSection = sectionThreads.contains(key)
            if !archived, inSection || (key == editing && (row != nil || old != nil)) { editable.insert(key) }
            let location: Any = project(id: id, row: row, fallback: archived ? nil : old) as Any? ?? NSNull()
            if inherited.contains(key) || inSection { locations[key] = location }
            if inSection, !archived, row != nil || old != nil {
                let title = (row?["display_title"]).flatMap { $0.isEmpty ? nil : $0 } ?? old?["name"] ?? id
                customThreads.append(["id": id, "key": key, "title": title, "projectId": location])
            }
        }
        let visibleProjects = projects.map { $0.filter { $0.key != "path" } }
        return (["account": account, "threads": threads, "projects": visibleProjects,
                 "projectAliases": aliases, "threadProjects": locations,
                 "customSections": customSections.map(\.json), "customThreads": customThreads,
                 "clientBindings": clientBindings], editable)
    }
}
