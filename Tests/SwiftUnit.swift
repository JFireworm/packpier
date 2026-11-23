import AppKit

@main enum SwiftUnit {
    @MainActor static func main() throws {
        try MarketApplicationsCheck.run()
        try WeChatOverlayCheck.run()
        try NativeUI.checkTime()
    }
}
