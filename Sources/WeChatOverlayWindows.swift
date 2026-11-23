import AppKit

@MainActor final class WeChatOverlayWindows {
    private(set) var tint: NSPanel
    private(set) var control: NSPanel
    private let picker: ConversationThemePicker
    private var geometry: WeChatOverlayGeometry?
    private var relativeTo: Int = 0
    private var desktopTop: CGFloat = 0
    private var colored = false

    init(preferences:UserDefaults) {
        func panel() -> NSPanel {
            let p = NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:true)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.hidesOnDeactivate = false; p.isFloatingPanel = false; p.level = .normal
            p.isMovable = false; p.becomesKeyOnlyIfNeeded = true; p.animationBehavior = .none
            p.collectionBehavior = [.transient,.ignoresCycle,.fullScreenAuxiliary]
            return p
        }
        tint = panel()
        tint.ignoresMouseEvents = true
        tint.backgroundColor = NSColor(srgbRed:0.28,green:0.71,blue:0.50,alpha:0.13)
        control = panel()
        let stack = NSStackView()
        control.contentView = stack
        picker = ConversationThemePicker(preferences:preferences,localize:{ PPText.get($0) })
        picker.attachOverlay(to:stack) { [weak self] palette in
            self?.colored = palette != nil
            self?.draw()
        }
    }

    func show(_ geometry:WeChatOverlayGeometry, desktopTop:CGFloat, above window:Int) {
        if self.geometry == geometry, self.desktopTop == desktopTop,
           relativeTo == window, control.isVisible, tint.isVisible == colored { return }
        self.geometry = geometry
        self.desktopTop = desktopTop
        self.relativeTo = window
        draw()
    }

    func hide() {
        geometry = nil
        control.orderOut(nil); tint.orderOut(nil)
    }

    private func draw() {
        guard let geometry else { return }
        func place(_ window:NSPanel,_ rect:CGRect) {
            let destination = WeChatOverlayGeometry.appKitRect(rect,desktopTop:desktopTop)
            if window.frame != destination { window.setFrame(destination,display:true) }
            window.order(.above,relativeTo:relativeTo)
        }
        if colored { place(tint,geometry.tint) } else { tint.orderOut(nil) }
        place(control,geometry.button)
    }
}
