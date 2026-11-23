import Foundation

typealias Fields = [String: Any]

enum PackpierError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
