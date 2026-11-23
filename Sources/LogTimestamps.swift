import Foundation

enum LogTimestamps {
    /// Only convert the RFC 3339 prefix written by the loader. The message may contain other dates.
    static func display(_ raw:String, in zone:TimeZone) -> String {
        let parser = ISO8601DateFormatter()
        let local = DateFormatter()
        local.locale = Locale(identifier:"en_US_POSIX")
        local.calendar = Calendar(identifier:.gregorian)
        local.timeZone = zone
        local.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return raw.components(separatedBy:"\n").map { line in
            guard let space = line.firstIndex(of:" "), line.distance(from:line.startIndex,to:space) >= 20 else { return line }
            let stamp = line[..<space]
            guard stamp[stamp.index(stamp.startIndex,offsetBy:10)] == "T" else { return line }
            let split = stamp.index(stamp.startIndex,offsetBy:19)
            let tail = stamp[split...]
            guard let tz = tail.firstIndex(where:{ $0 == "Z" || $0 == "+" || $0 == "-" }) else { return line }
            let fraction = tail[..<tz]
            guard fraction.isEmpty || (fraction.first == "." && (2...10).contains(fraction.count) && fraction.dropFirst().allSatisfy(\.isNumber)),
                  let date = parser.date(from:String(stamp[..<split]) + stamp[tz...]) else { return line }
            let millis = fraction.isEmpty ? "" : "." + (String(fraction.dropFirst())+"000").prefix(3)
            return local.string(from:date) + millis + line[space...]
        }.joined(separator:"\n")
    }
}
