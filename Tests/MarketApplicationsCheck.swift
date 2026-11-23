import Foundation

enum MarketApplicationsCheck {
    @MainActor static func run() throws {
        let defaults = UserDefaults.standard
        let domain = UserDefaults.argumentDomain
        let original = defaults.volatileDomain(forName: domain)
        defer { defaults.setVolatileDomain(original, forName: domain) }
        let key = "packpier.marketApplications.v1"
        let previous = Data(#"{"apps":[{"name":"DingTalk","bundleID":"com.example.dingtalk"},{"name":"微信","bundleID":"com.tencent.xinWeChat"}],"selectedID":"com.tencent.xinwechat"}"#.utf8)
        defaults.setVolatileDomain(original.merging([key: previous]) { _, new in new }, forName: domain)
        let manager = Manager()
        manager.showInstalled(for: .codex, matching: "prism")
        manager.showInstalled(for: .wechat, matching: "wechat-celadon")
        guard manager.target == .codex, manager.selectedPackageID == "prism",
              defaults.data(forKey: key) == previous else {
            throw PackpierError.message("A saved experimental target replaced Codex or changed its preferences")
        }
        print("PASS release target stays Codex with legacy app preferences")
    }
}
