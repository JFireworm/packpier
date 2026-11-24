import Foundation
import CoreFoundation
import Darwin

typealias JSONObject = [String: Any]

enum WireError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

func jsonObject(_ value: Any?) -> JSONObject? { value as? JSONObject }
func jsonArray(_ value: Any?) -> [Any]? { value as? [Any] }
func jsonString(_ value: Any?) -> String? { value as? String }
func jsonInt(_ value: Any?) -> Int? {
    if let number = value as? NSNumber, !(value is Bool) { return number.intValue }
    return value as? Int
}
func jsonBool(_ value: Any?) -> Bool? {
    if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
    return value as? Bool
}
func jsonDouble(_ value: Any?) -> Double? {
    if let number = value as? NSNumber, !(value is Bool) { return number.doubleValue }
    return value as? Double
}

func jsonStringList(_ value: Any?) -> [String]? { value as? [String] }

/// Deep copy through the JSON encoder so mutations never alias the caller's dictionaries.
func jsonClone(_ value: Any) -> Any {
    guard let data = try? JSONSerialization.data(withJSONObject: value),
          let copy = try? JSONSerialization.jsonObject(with: data) else { return value }
    return copy
}

func readJSONObject(_ url: URL) throws -> JSONObject {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
        throw WireError.message("Invalid JSON in " + url.lastPathComponent)
    }
    return object
}

func writeJSONObject(_ object: JSONObject, to url: URL, permissions: Int = 0o600) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let temp = directory.appendingPathComponent(".packpier-" + UUID().uuidString)
    let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(permissions))
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { try? FileManager.default.removeItem(at: temp) }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    try handle.write(contentsOf: data)
    try handle.close()
    guard Darwin.rename(temp.path, url.path) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

/// Value embedded into a JavaScript expression as a JSON literal.
func jsonLiteral(_ value: Any) -> String {
    if value is NSNull { return "null" }
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let text = String(data: data, encoding: .utf8) else { return "null" }
    return text
}

func isoNow() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}
