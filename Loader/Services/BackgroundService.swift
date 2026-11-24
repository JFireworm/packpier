import AppKit
import CryptoKit
import Darwin
import ImageIO
import UniformTypeIdentifiers

actor BackgroundService {
    static let maxBytes = 48 * 1024 * 1024
    static let chunkSize = 30 * 1024
    private struct Upload {
        var data = Data()
        var updated = ContinuousClock.now
    }
    private var uploads: [String: Upload] = [:]
    private let favorites: URL
    private let downloads: URL
    private let provider: BackgroundProvider

    init(home: URL, provider: BackgroundProvider = BackgroundProvider()) {
        favorites = home.appendingPathComponent("Pictures/Packpier/收藏", isDirectory: true)
        downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        self.provider = provider
    }

    func upload(id: String, offset: Int, base64: String, cancel: Bool = false) throws {
        let cutoff = ContinuousClock.now - .seconds(60)
        uploads = uploads.filter { $0.value.updated >= cutoff }
        guard id.range(of: #"\A[a-f0-9-]{36}\z"#, options: .regularExpression) != nil else {
            throw WireError.message("无效的图片传输标识")
        }
        if cancel { uploads.removeValue(forKey: id); return }
        guard base64.utf8.count <= Self.chunkSize * 4 / 3, let bytes = Data(base64Encoded: base64), !bytes.isEmpty,
              bytes.count <= Self.chunkSize,
              uploads[id] != nil || (offset == 0 && uploads.count < 3),
              offset == (uploads[id]?.data.count ?? 0), offset <= Self.maxBytes - bytes.count else {
            throw WireError.message("无效的图片数据块")
        }
        uploads[id, default: Upload()].data.append(bytes)
        uploads[id]?.updated = .now
    }

    private func openFavorite(_ name: String) throws -> (FileHandle, Int) {
        guard name.range(of: #"\A[a-f0-9]{64}\.(png|jpg|webp|gif|avif|heic|tif|bmp)\z"#, options: .regularExpression) != nil else {
            throw WireError.message("无效的收藏文件名")
        }
        let fd = Darwin.open(favorites.appendingPathComponent(name).path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var stat = Darwin.stat()
        guard fstat(fd, &stat) == 0, stat.st_mode & S_IFMT == S_IFREG,
              stat.st_size > 0 && stat.st_size <= Self.maxBytes else { throw WireError.message("无效的收藏图片") }
        return (handle, Int(stat.st_size))
    }

    func read(file: String, offset: Int) throws -> JSONObject {
        let (handle, size) = try openFavorite(file)
        defer { try? handle.close() }
        guard (0..<size).contains(offset) else { throw WireError.message("无效的图片偏移量") }
        try handle.seek(toOffset: UInt64(offset))
        guard let bytes = try handle.read(upToCount: min(Self.chunkSize, size - offset)), !bytes.isEmpty else {
            throw WireError.message("收藏文件不完整")
        }
        return ["size": size, "data": bytes.base64EncodedString()]
    }

    static func imageExtension(_ data: Data) throws -> String {
        let bytes = Array(data.prefix(32))
        func text(_ start: Int, _ end: Int) -> String {
            String(decoding: bytes.dropFirst(start).prefix(end - start), as: UTF8.self)
        }
        if bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return "png" }
        if bytes.starts(with: [255, 216, 255]) { return "jpg" }
        if text(0, 4) == "RIFF", text(8, 12) == "WEBP" { return "webp" }
        if ["GIF87a", "GIF89a"].contains(text(0, 6)) { return "gif" }
        if text(4, 8) == "ftyp" {
            let brands = text(8, 32)
            if ["avif", "avis"].contains(where: brands.contains) { return "avif" }
            if ["heic", "heix", "mif1"].contains(where: brands.contains) { return "heic" }
        }
        if bytes.starts(with: [73, 73, 42, 0]) || bytes.starts(with: [77, 77, 0, 42]) { return "tif" }
        if text(0, 2) == "BM" { return "bmp" }
        throw WireError.message("不支持的图片格式")
    }

    private func publish(_ bytes: Data, directory: URL, name: String, deduplicate: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temp = directory.appendingPathComponent(".packpier-" + UUID().uuidString)
        let fd = Darwin.open(temp.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { try? fm.removeItem(at: temp) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: bytes)
        try handle.close()
        if Darwin.link(temp.path, directory.appendingPathComponent(name).path) != 0 {
            guard deduplicate && errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let (existing, size) = try openFavorite(name)
            defer { try? existing.close() }
            guard size == bytes.count, try existing.read(upToCount: size + 1) == bytes else {
                throw WireError.message("收藏文件内容不一致")
            }
        }
    }

    static func clipboardImages(_ data: Data) throws -> [NSPasteboard.PasteboardType: Data] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 64_000_000 / height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw WireError.message("无法解码图片") }
        var result: [NSPasteboard.PasteboardType: Data] = [:]
        for (type, format) in [(UTType.png, NSPasteboard.PasteboardType.png), (.tiff, .tiff)] {
            let bytes = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil) else {
                throw WireError.message("无法转换图片")
            }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else {
                throw WireError.message("无法复制图片")
            }
            result[format] = bytes as Data
        }
        return result
    }

    @MainActor private static func copy(_ images: [NSPasteboard.PasteboardType: Data]) throws {
        let item = NSPasteboardItem()
        for (type, bytes) in images {
            guard item.setData(bytes, forType: type) else { throw WireError.message("无法写入图片格式") }
        }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { throw WireError.message("剪贴板拒绝了图片") }
    }

    func action(_ action: String, file: String? = nil, upload: String? = nil, source: URL? = nil) async throws -> JSONObject {
        guard ["favorite", "save", "copy"].contains(action) else { throw WireError.message("不支持的图片操作") }
        let bytes: Data
        if let file, !file.isEmpty {
            do {
                let (handle, size) = try openFavorite(file)
                defer { try? handle.close() }
                guard let data = try handle.read(upToCount: size + 1), data.count == size else {
                    throw WireError.message("收藏文件已变化")
                }
                bytes = data
            } catch let error as POSIXError where error.code == .ENOENT { return ["missing": true] }
        } else if let upload, !upload.isEmpty {
            guard let item = uploads.removeValue(forKey: upload), item.updated >= .now - .seconds(60) else {
                throw WireError.message("图片传输已过期")
            }
            bytes = item.data
        } else if let source { bytes = try await provider.image(at: source) }
        else { throw WireError.message("缺少图片来源") }
        let ext = try Self.imageExtension(bytes)
        if action == "copy" {
            let images = try Self.clipboardImages(bytes)
            try await Self.copy(images)
            return ["copied": true]
        }
        if action == "favorite" {
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let name = digest + "." + ext
            try publish(bytes, directory: favorites, name: name, deduplicate: true)
            return ["file": name]
        }
        let date = isoNow().replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-")
        let name = "Packpier-" + date + "-" + UUID().uuidString.lowercased().prefix(8) + "." + ext
        try publish(bytes, directory: downloads, name: name, deduplicate: false)
        return ["file": name]
    }
}
