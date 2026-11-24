import CryptoKit
import Foundation

/// Execute the same immutable copy of the package that the user reviewed.
final class NodeSource {
    let folder: URL
    let entry: URL
    let token: String

    init(package: URL, manifest: Object, path: String) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("packpier-node-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let zip = package.appendingPathComponent(".packpier-source.zip")
            if fm.fileExists(atPath: zip.path) {
                guard try zip.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
                    throw LibraryError("Invalid plugin archive")
                }
                try LocalPackage(source: zip).copyNodeSources(to: root)
            } else {
                try Self.copyDirectory(package, to: root)
            }
            let entry = root.appendingPathComponent(path).standardizedFileURL
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
                  entry.path.hasPrefix(root.standardizedFileURL.path + "/"),
                  try entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw LibraryError("Invalid Node plugin entry")
            }
            let data = try Data(contentsOf: root.appendingPathComponent("package.json"))
            guard let copied = try JSONSerialization.jsonObject(with: data) as? NSDictionary,
                  copied.isEqual(to: manifest) else { throw LibraryError("Plugin manifest differs from installed package") }
            var hash = SHA256()
            let files = try fm.subpathsOfDirectory(atPath: root.path).sorted()
            for name in files {
                let file = root.appendingPathComponent(name)
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                hash.update(data: Data(name.utf8))
                hash.update(data: Data([0]))
                hash.update(data: Data(SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe))))
            }
            self.token = hash.finalize().map { String(format: "%02x", $0) }.joined()
            self.folder = root
            self.entry = entry
        } catch {
            try? fm.removeItem(at: root)
            throw error
        }
    }

    private static func copyDirectory(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        var listingError: Error?
        guard let entries = fm.enumerator(at: source, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in
            listingError = error
            return false
        }) else { throw LibraryError("Cannot read plugin directory") }
        var count = 0, remaining = 64 * 1024 * 1024
        for case let file as URL in entries {
            count += 1
            let values = try file.resourceValues(forKeys: keys)
            guard count <= 4096, values.isSymbolicLink == false else { throw LibraryError("Invalid plugin source tree") }
            let relative = String(file.path.dropFirst(source.path.count + 1))
            let target = destination.appendingPathComponent(relative)
            if values.isDirectory == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                guard values.isRegularFile == true, let size = values.fileSize, size <= remaining else {
                    throw LibraryError("Invalid or oversized plugin source")
                }
                remaining -= size
                try fm.copyItem(at: file, to: target)
            }
        }
        if let listingError { throw listingError }
    }

    deinit { try? FileManager.default.removeItem(at: folder) }
}
