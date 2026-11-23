import AppKit
import XCTest
import WeChatCeladon

final class ThemeTests: XCTestCase {
    @MainActor func testMenuAndRestoration() throws {
        _ = NSApplication.shared
        let suite = "local.packpier.celadon-test." + UUID().uuidString
        let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let search = NSSearchField(), add = NSButton()
        let bar = NSStackView(views: [search, add])
        bar.orientation = .horizontal
        let picker = ConversationThemePicker(preferences: prefs)
        var updates = [ConversationPalette?]()
        func attach() -> Bool {
            picker.attach(to: bar, search: search, add: add) { updates.append($0) }
        }
        XCTAssertTrue(attach())
        XCTAssertFalse(attach())
        XCTAssertEqual(bar.arrangedSubviews.count, 3)
        XCTAssertTrue(bar.arrangedSubviews.first === search && bar.arrangedSubviews.last === add)
        XCTAssertEqual(updates.count, 1)
        XCTAssertNil(updates[0])
        let button = try XCTUnwrap(bar.arrangedSubviews[1] as? NSButton)
        let menu = try XCTUnwrap(button.menu)
        XCTAssertEqual(menu.items.map(\.title), ["微信默认", "青瓷"])
        XCTAssertEqual(menu.items[0].state, .on)
        menu.performActionForItem(at: 1)
        let palette = try XCTUnwrap(updates.last ?? nil)
        XCTAssertEqual(palette.row(isPinned: true, isSelected: true), palette.selected)
        XCTAssertEqual(palette.row(isPinned: true, isSelected: false), palette.pinned)
        XCTAssertEqual(palette.row(isPinned: false, isSelected: false), palette.background)
        picker.detach()
        XCTAssertEqual(bar.arrangedSubviews.count, 2)
        XCTAssertNil(updates.last ?? nil)
        XCTAssertTrue(attach())
        XCTAssertEqual(menu.items[1].state, .on)
        menu.performActionForItem(at: 0)
        XCTAssertNil(updates.last ?? nil)
        XCTAssertEqual(menu.items[0].state, .on)
        picker.detach()
        let other = NSStackView(views: [search, NSButton(), add])
        other.orientation = .horizontal
        XCTAssertFalse(picker.attach(to: other, search: search, add: add) { _ in XCTFail("Unexpected repaint") })
    }
}
