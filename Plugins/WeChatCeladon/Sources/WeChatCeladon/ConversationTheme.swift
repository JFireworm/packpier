import AppKit

public struct ConversationPalette {
    public let background: NSColor
    public let pinned: NSColor
    public let selected: NSColor
    public let title: NSColor
    public let summary: NSColor
    public let accent: NSColor

    public func row(isPinned: Bool, isSelected: Bool) -> NSColor {
        if isSelected { return selected }
        return isPinned ? pinned : background
    }

    public static let celadon = ConversationPalette(
        background: rgb(0xF2F7F4), pinned: rgb(0xE2EEE8), selected: rgb(0xC4DDD1),
        title: rgb(0x203A31), summary: rgb(0x596E62), accent: rgb(0x32785B)
    )

    private static func rgb(_ value: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

/// A host that owns the search toolbar supplies its views and redraws its list
/// through applyPalette. Passing nil restores the host's normal rendering.
@MainActor public final class ConversationThemePicker: NSObject {
    private let defaults: UserDefaults
    private static let preference = "wechat.conversationList.theme"
    private let button = NSButton()
    private let choices = NSMenu()
    private weak var toolbar: NSStackView?
    private var applyPalette: ((ConversationPalette?) -> Void)?
    private var usesCeladon: Bool { defaults.string(forKey: Self.preference) == "celadon" }

    public init(preferences: UserDefaults, localize: (String) -> String = { $0 }) {
        defaults = preferences
        super.init()
        button.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.toolTip = localize("会话列表主题")
        button.setAccessibilityLabel(localize("会话列表主题"))
        button.target = self
        button.action = #selector(showMenu)
        choices.autoenablesItems = false
        for title in ["微信默认", "青瓷"] {
            let item = choices.addItem(withTitle: localize(title), action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
        }
        button.menu = choices
    }

    /// Returns false when the supplied layout cannot provide the requested slot.
    @discardableResult public func attach(to toolbar: NSStackView, search: NSView, add: NSView,
                                          applyPalette: @escaping (ConversationPalette?) -> Void) -> Bool {
        guard self.toolbar == nil, toolbar.orientation == .horizontal,
              let index = toolbar.arrangedSubviews.firstIndex(of: search),
              toolbar.arrangedSubviews.dropFirst(index + 1).first === add else { return false }
        toolbar.insertArrangedSubview(button, at: index + 1)
        self.toolbar = toolbar
        self.applyPalette = applyPalette
        refresh()
        return true
    }

    public func attachOverlay(to slot: NSStackView, applyPalette: @escaping (ConversationPalette?) -> Void) {
        guard toolbar == nil else { return }
        button.bezelStyle = .inline
        button.isBordered = false
        button.controlSize = .small
        slot.addArrangedSubview(button)
        toolbar = slot
        self.applyPalette = applyPalette
        refresh()
    }

    public func detach() {
        guard let applyPalette else { return }
        self.applyPalette = nil
        toolbar?.removeArrangedSubview(button)
        button.removeFromSuperview()
        toolbar = nil
        applyPalette(nil)
    }

    @objc private func showMenu() {
        choices.popUp(positioning: nil, at: NSPoint(x: 0, y: button.isFlipped ? button.bounds.maxY : 0), in: button)
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard toolbar != nil, sender.menu === choices else { return }
        let celadon = sender === choices.items.last
        guard celadon != usesCeladon else { return }
        if celadon { defaults.set("celadon", forKey: Self.preference) }
        else { defaults.removeObject(forKey: Self.preference) }
        refresh()
    }

    private func refresh() {
        let celadon = usesCeladon
        choices.items[0].state = celadon ? .off : .on
        choices.items[1].state = celadon ? .on : .off
        button.contentTintColor = celadon ? ConversationPalette.celadon.accent : nil
        applyPalette?(celadon ? .celadon : nil)
    }
}
