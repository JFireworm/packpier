import AppKit
import SwiftUI

/// All pointer positions are in the window's bottom-up coordinate space.
@MainActor final class PackageDrag: ObservableObject {
    struct Slot: Equatable { let id: String; let after: Bool }
    let rows = NSHashTable<PackageRowBounds>.weakObjects()
    @Published private(set) var source: String?
    @Published private(set) var slot: Slot?
    private var badge: NSTextField?
    private var resigned: NSObjectProtocol?

    func track(id: String, title: String, event: NSEvent, handle: NSView) {
        guard let window = handle.window, let content = window.contentView else { cancel(); return }
        if source == nil {
            source = id
            let badge = NSTextField(labelWithString:title)
            badge.font = .systemFont(ofSize:NSFont.systemFontSize,weight:.semibold)
            badge.alignment = .center
            badge.textColor = .white
            badge.lineBreakMode = .byTruncatingTail
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            badge.layer?.cornerRadius = 6
            badge.setFrameSize(NSSize(width:min(230,max(54,badge.intrinsicContentSize.width+20)),height:badge.intrinsicContentSize.height+2))
            badge.setAccessibilityElement(false)
            content.addSubview(badge,positioned:.above,relativeTo:nil)
            self.badge = badge
            resigned = NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,
                object:window,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } }
        }
        guard source == id else { return }
        _ = handle.autoscroll(with:event)
        let point = event.locationInWindow
        let p = content.convert(point,from:nil)
        badge?.setFrameOrigin(NSPoint(x:p.x+14,y:p.y+(content.isFlipped ? 10 : -25)))
        let next = destination(at:point, window:window)
        if next != slot { slot = next }
        NSCursor.closedHand.set()
    }

    func destination(at point:NSPoint, window:NSWindow) -> Slot? {
        for row in rows.allObjects where row.window === window {
            let local = row.convert(point,from:nil)
            let visible = row.visibleRect.intersection(row.bounds)
            if !visible.isEmpty && visible.insetBy(dx:0,dy:-0.5).contains(local) {
                let below = row.isFlipped ? local.y >= row.bounds.midY : local.y <= row.bounds.midY
                return Slot(id:row.packageID,after:below)
            }
        }
        return nil
    }
    func cancel() {
        if let resigned { NotificationCenter.default.removeObserver(resigned) }
        resigned = nil
        badge?.removeFromSuperview()
        badge = nil
        if slot != nil { slot = nil }
        if source != nil { source = nil; NSCursor.arrow.set() }
    }
}

final class PackageRowBounds: NSView {
    var packageID = ""
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
}
struct PackageRowRegion: NSViewRepresentable {
    let id: String
    let drag: PackageDrag
    func makeNSView(context:Context) -> PackageRowBounds {
        let view = PackageRowBounds()
        view.packageID = id
        drag.rows.add(view)
        return view
    }
    func updateNSView(_ view:PackageRowBounds,context:Context) { view.packageID = id }
}

struct PackageGrip: NSViewRepresentable {
    let id: String
    let title: String
    let drag: PackageDrag
    let enabled: Bool
    let move: (String,Bool) -> Void
    let step: (Bool) -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    func makeNSView(context:Context) -> GripView { GripView() }
    func updateNSView(_ view:GripView, context:Context) {
        view.packageID = id
        view.title = title
        view.drag = drag
        view.enabled = enabled
        view.move = move
        view.step = step
        view.canMoveUp = canMoveUp
        view.canMoveDown = canMoveDown
        view.toolTip = PPText.get("拖动以调整加载顺序")
        view.setAccessibilityLabel(PPText.format("调整 %@ 的加载顺序",title))
        view.needsDisplay = true
    }
}

final class GripView: NSView {
    var packageID = "", title = ""
    weak var drag:PackageDrag?
    var enabled = true, canMoveUp = false, canMoveDown = false
    var move: ((String,Bool)->Void)?
    var step: ((Bool)->Void)?
    private var origin:NSPoint?
    private var hovering = false
    private var area:NSTrackingArea?
    override var acceptsFirstResponder: Bool { enabled }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect:.zero,options:[.activeInKeyWindow,.inVisibleRect,.mouseEnteredAndExited],owner:self,userInfo:nil)
        addTrackingArea(a); area = a
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if enabled { addCursorRect(bounds,cursor:.openHand) }
    }
    override func mouseEntered(with event:NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event:NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect:NSRect) {
        (enabled && hovering ? NSColor.labelColor : NSColor.secondaryLabelColor).setFill()
        for x in -1...1 {
            for y in -1...1 {
                let p = NSPoint(x:bounds.midX + CGFloat(x)*4.6, y:bounds.midY + CGFloat(y)*4.6)
                NSBezierPath(ovalIn:NSRect(x:p.x-0.85,y:p.y-0.85,width:1.7,height:1.7)).fill()
            }
        }
    }
    override func mouseDown(with event:NSEvent) {
        guard enabled else { return }
        window?.makeFirstResponder(self)
        origin = event.locationInWindow
    }
    override func mouseDragged(with event:NSEvent) {
        guard enabled, let origin else { return }
        let p = event.locationInWindow
        if drag?.source == packageID || hypot(p.x-origin.x,p.y-origin.y) >= 3 {
            drag?.track(id:packageID,title:title,event:event,handle:self)
        }
    }
    override func mouseUp(with event:NSEvent) {
        defer { origin = nil }
        guard let drag, drag.source == packageID else { return }
        let target = window.flatMap { drag.destination(at:event.locationInWindow,window:$0) }
        drag.cancel()
        if enabled, let target, target.id != packageID { move?(target.id,target.after) }
    }
    override func cancelOperation(_ sender:Any?) { origin = nil; drag?.cancel() }
    override func keyDown(with event:NSEvent) {
        switch event.keyCode {
        case 53: cancelOperation(nil)
        case 126 where enabled && canMoveUp: step?(false)
        case 125 where enabled && canMoveDown: step?(true)
        default: super.keyDown(with:event)
        }
    }
    override func viewWillMove(toWindow window:NSWindow?) {
        if window == nil, drag?.source == packageID { cancelOperation(nil) }
        super.viewWillMove(toWindow:window)
    }
    override func menu(for event:NSEvent) -> NSMenu? {
        guard enabled else { return nil }
        let menu = NSMenu()
        for (down,key) in [(false,"向上移动"),(true,"向下移动")] where down ? canMoveDown : canMoveUp {
            let item = menu.addItem(withTitle:PPText.get(key),action:#selector(stepMenu(_:)),keyEquivalent:"")
            item.target = self; item.tag = down ? 1 : 0
        }
        return menu
    }
    @objc private func stepMenu(_ sender:NSMenuItem) { step?(sender.tag == 1) }
}
