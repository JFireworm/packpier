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
    let account: String
    let projects: [[String: String]]
    let aliases: [String: String]
    private let pins: [String]
    private let assignments: [String: [String: String]]
    private let catalog: ThreadLookup
    private let legacy: ThreadLookup

    init(root: URL) throws {
        let state = try readJSONObject(root.appendingPathComponent(".codex-global-state.json"))
        let prefix = "electron-owner-atoms:"
        let owners = state.keys.filter { $0.hasPrefix(prefix) }
        let selected = (state["electron-renderer-content-owner"] as? String).map { prefix + $0 }
        guard let owner = selected.flatMap({ owners.contains($0) ? $0 : nil }) ?? (owners.count == 1 ? owners.first : nil),
              let atoms = state[owner] as? JSONObject else {
            throw WireError.message("无法确定当前 Codex 账户")
        }
        account = String(owner.dropFirst(prefix.count))
        guard account.range(of: #"\A[a-zA-Z0-9_-]{1,128}\z"#, options: .regularExpression) != nil else {
            throw WireError.message("无效账户标识")
        }
        guard let pinned = atoms["app-server-pinned-thread-order-v1"] as? [String] else {
            throw WireError.message("当前 Codex 置顶数据格式不受支持")
        }
        var seen: Set<String> = []
        pins = pinned.filter { seen.insert($0).inserted }
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
        catalog = try ThreadLookup(root.appendingPathComponent("sqlite/codex.db"), sql:
            "SELECT display_title, cwd, project_id FROM local_thread_catalog WHERE thread_id=? AND host_id='local'")
        legacy = try ThreadLookup(root.appendingPathComponent("state_5.sqlite"), sql:
            "SELECT name, cwd, archived FROM threads WHERE id=?")
    }

    private func project(id: String, row: [String: String]?, fallback: [String: String]?) -> String? {
        if let assigned = assignments[id]?["projectId"], !assigned.isEmpty { return assigned }
        if let native = row?["project_id"], !native.isEmpty { return aliases[native] ?? native }
        let cwd = row?["cwd"].flatMap { $0.isEmpty ? nil : $0 } ?? fallback?["cwd"]
        return projects.first(where: { $0["path"] == cwd })?["id"]
    }

    func sidebar(inherited: Set<String>, editing: String?) throws -> (state: JSONObject, editable: Set<String>) {
        var threads: [JSONObject] = []
        var locations: JSONObject = [:]
        var editable = Set(projects.compactMap { $0["id"].map { "project:" + $0 } })
        for (index, id) in pins.enumerated() {
            let row = try catalog.row(id)
            let old = try legacy.row(id)
            guard (Int(old?["archived"] ?? "") ?? 0) == 0,
                  !(row?["display_title"] ?? "").isEmpty || !(old?["name"] ?? "").isEmpty else { continue }
            let key = Self.threadPrefix + id
            let location: Any = project(id: id, row: row, fallback: old) as Any? ?? NSNull()
            threads.append(["id": id, "kind": "codex", "hostId": "local", "projectId": location, "nativeIndex": index + 1])
            locations[key] = location
            editable.insert(key)
        }
        for key in inherited.union(editing.map { [$0] } ?? []) where key.hasPrefix(Self.threadPrefix) && locations[key] == nil {
            let id = String(key.dropFirst(Self.threadPrefix.count))
            guard !id.isEmpty else { continue }
            let row = try catalog.row(id)
            let old = try legacy.row(id)
            let archived = (Int(old?["archived"] ?? "") ?? 0) != 0
            if key == editing, !pins.contains(id), !archived, row != nil || old != nil { editable.insert(key) }
            if inherited.contains(key) {
                locations[key] = project(id: id, row: row, fallback: archived ? nil : old) as Any? ?? NSNull()
            }
        }
        let visibleProjects = projects.map { $0.filter { $0.key != "path" } }
        return (["account": account, "threads": threads, "projects": visibleProjects,
                 "projectAliases": aliases, "threadProjects": locations], editable)
    }
}
