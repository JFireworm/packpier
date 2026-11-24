import Foundation

// The host receives the same private copy that the user previewed.
final class LocalPackage: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
    let manifestData: Data
    let name: String
    let version: String
    let reason: String?
    private let memberNames: [String]
    private let manifestMember: String
    private let staging: URL

    init(source: URL) throws {
        let fm = FileManager.default
        let traits = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard source.isFileURL, source.pathExtension.lowercased() == "zip", traits.isRegularFile == true,
              let size = traits.fileSize, size <= 536_870_912 else { throw PackpierError.message("请选择 512 MB 以内的本地 ZIP 插件包。") }
        let temp = fm.temporaryDirectory.appendingPathComponent("packpier-import-" + UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700])
        let archive = temp.appendingPathComponent("package.zip")
        do {
            try fm.copyItem(at: source, to: archive)
            let listing = try Self.unzip(["-Z1", archive.path], limit: 2_000_000)
            let names = String(decoding: listing, as: UTF8.self).split(separator:"\n").map(String.init)
            let manifests = names.filter { name in
                let parts = name.split(separator:"/", omittingEmptySubsequences:false)
                return parts.count == 2 && parts.last == "package.json" && parts[0] != "__MACOSX"
            }
            let entry = names.contains("package.json") ? "package.json" : manifests.count == 1 ? manifests[0] : ""
            guard !entry.isEmpty, names.filter({ $0 == entry }).count == 1,
                  entry.split(separator:"/", omittingEmptySubsequences:false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  entry.range(of: #"^[\p{L}\p{N}._+ @/-]+$"#, options:.regularExpression) != nil else {
                throw PackpierError.message("ZIP 中应有一个位于根目录或一级目录的 package.json。")
            }
            let data = try Self.unzip(["-p",archive.path,entry], limit: 262144)
            guard let manifest = try JSONSerialization.jsonObject(with: data) as? Fields,
                  let name = manifest["name"] as? String, !name.isEmpty,
                  let version = manifest["version"] as? String, !version.isEmpty,
                  let target = (manifest["packpier"] ?? manifest["codexTweaks"]) as? Fields, target["apiVersion"] as? Int == 3 else {
                throw PackpierError.message("这个 ZIP 缺少有效的 Codex v3 插件包清单。")
            }
            guard manifest["packpier"] == nil || manifest["codexTweaks"] == nil else {
                throw PackpierError.message("插件清单含有重复的适配器声明。")
            }
            self.manifestData = data
            self.memberNames = names
            self.manifestMember = entry
            self.name = name
            self.version = version
            self.reason = ((target["permissions"] as? Fields)?["node"] as? Fields)?["reason"] as? String
            self.fileName = source.lastPathComponent
            self.url = archive
            self.staging = temp
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
    deinit { try? FileManager.default.removeItem(at: staging) }

    /// Copy member bytes into a new private directory. Archive symlinks, permissions and
    /// absolute paths are never materialized by an archive extractor.
    func copyNodeSources(to destination: URL) throws {
        let prefix = String(manifestMember.dropLast("package.json".count))
        var remaining = 64 * 1024 * 1024
        guard memberNames.count <= 4096 else { throw PackpierError.message("Too many files in plugin archive") }
        for name in memberNames where name.hasPrefix(prefix) && !name.hasSuffix("/") {
            let path = String(name.dropFirst(prefix.count))
            if path.hasPrefix("__MACOSX/") { continue }
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            // unzip -p accepts wildcard patterns. Only pass unambiguous literal member names.
            guard name.first != "-", name.range(of: #"[\x00-\x1f\x7f\\*?\[\]]"#, options: .regularExpression) == nil,
                  !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw PackpierError.message("Invalid path in plugin archive")
            }
            let bytes = try Self.unzip(["-p", url.path, name], limit: remaining)
            remaining -= bytes.count
            let target = destination.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: target, options: .withoutOverwriting)
        }
    }

    private static func unzip(_ args: [String], limit: Int) throws -> Data {
        let child = Process(), pipe = Pipe()
        child.executableURL = URL(fileURLWithPath:"/usr/bin/unzip")
        child.arguments = args
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        child.standardInput = FileHandle.nullDevice
        try child.run()
        defer {
            try? pipe.fileHandleForReading.close()
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }
        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount:65536), !chunk.isEmpty {
            guard data.count + chunk.count <= limit else { throw PackpierError.message("ZIP 清单超过大小限制。") }
            data.append(chunk)
        }
        child.waitUntilExit()
        guard child.terminationStatus == 0 else { throw PackpierError.message("无法读取 ZIP，请重新选择插件包。") }
        return data
    }
}
