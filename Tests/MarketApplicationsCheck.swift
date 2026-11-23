import Foundation

enum MarketApplicationsCheck {
    @MainActor static func run() throws {
        let suite = "packpier.market-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        func require(_ condition:Bool,_ message:String) throws {
            if !condition { throw PackpierError.message(message) }
        }

        let first = Manager(defaults:defaults)
        let codex = MarketApp.known(.codex), wechat = MarketApp.known(.wechat)
        try require(first.marketApps.apps == [codex] && first.target == .codex,"Only Codex should appear on first launch")
        first.removeMarketApp(codex)
        let reopened = Manager(defaults:defaults)
        try require(reopened.marketApps.apps.isEmpty && reopened.marketApps.selected == nil,"Removed Codex came back on launch")
        reopened.openCodexMarket()
        try require(reopened.addingMarketApp && reopened.marketApps.apps.isEmpty,"Overview silently re-added Codex")
        try require(MarketApp.catalog.contains(codex),"Codex is missing from Add App")
        reopened.addMarketApp(codex)
        reopened.addMarketApp(wechat)
        reopened.selectMarketApp(codex.id)
        reopened.showInstalled(for:.codex,matching:"p-sign")
        try require(reopened.selectedPackageID == "p-sign" && reopened.target == .codex && Manager(defaults:defaults).target == .codex,"Lost selection between tabs or on launch")
        reopened.addMarketApp(codex)
        try require(reopened.marketApps.apps == [codex,wechat],"Duplicate app or changed order")
        reopened.removeMarketApp(codex)
        try require(reopened.target == .wechat,"Did not select the remaining app")
        let other = MarketApp(bundleID:"test.market.custom",name:"Example",path:"/Applications/Example.app")
        reopened.addMarketApp(other)
        try require(reopened.marketApps.selected == other && reopened.target == nil,"Custom app acquired the wrong adapter")
        print("PASS first launch, explicit empty on reopen, Add App directory, overview, duplicate selection, custom adapter and remaining selection")
    }
}

