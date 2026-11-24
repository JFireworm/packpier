import Foundation

enum BuiltInPackages {
    static let sign = "p-sign"
    static let background = "custom-background"
    static let ids: Set<String> = [sign, "prism", background]

    static func upgradesBackground(from old: String, to new: String) -> Bool {
        let legacy = ["1.3.14", "1.3.15", "1.3.16"].contains(old) ||
            old.range(of: #"^1\.3\.14-packpier\.[1-5]$"#, options: .regularExpression) != nil
        return (new == "1.3.17" && legacy) ||
            (new == "1.3.19" && (legacy || ["1.3.17", "1.3.18"].contains(old)))
    }
}
