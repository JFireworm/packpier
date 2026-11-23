import AppKit

@MainActor enum WeChatOverlayCheck {
    static func run() throws {
        if WeChatOverlayTarget.compatible(WeChatOverlayTarget.installedURL) {
            guard let live = WeChatOverlayTarget.find(test:false), live.permitted, live.stagingOwner == nil,
                  live.url.path == WeChatOverlayTarget.installedURL.resolvingSymlinksInPath().path,
                  WeChatOverlayTarget.find(test:true)?.url.path != live.url.path else {
                throw PackpierError.message("Production and test overlay target isolation failed")
            }
        }
        let compact = CGRect(x:0,y:33,width:414,height:780)
        let field = CGRect(x:77,y:52,width:282,height:26)
        let rows = CGRect(x:61,y:94,width:350,height:719)
        guard let compactLayout = WeChatOverlayGeometry(window:compact,search:field,list:rows),
              field.contains(compactLayout.button),compactLayout.tint == rows,
              WeChatOverlayGeometry(window:compact,search:field.offsetBy(dx:250,dy:0),list:rows) == nil else {
            throw PackpierError.message("Incorrect compact WeChat sidebar geometry")
        }
        let suite = "local.packpier.overlay-test." + UUID().uuidString
        let preferences = UserDefaults(suiteName:suite)!
        defer { preferences.removePersistentDomain(forName:suite) }
        let host = NSWindow(contentRect:NSRect(x:100,y:120,width:800,height:460),
                            styleMask:[.borderless],backing:.buffered,defer:false)
        let root = NSView(frame:host.frame)
        host.contentView = root
        let search = NSSearchField(frame:NSRect(x:65,y:418,width:230,height:24))
        let list = NSScrollView(frame:NSRect(x:52,y:0,width:275,height:405))
        let content = NSView(frame:NSRect(x:0,y:0,width:275,height:1000))
        let row = NSButton(checkboxWithTitle:"Sample conversation",target:nil,action:nil)
        row.frame = NSRect(x:12,y:675,width:190,height:34)
        content.addSubview(row)
        list.documentView = content
        root.addSubview(search); root.addSubview(list)
        host.orderBack(nil)
        let windows = WeChatOverlayWindows(preferences:preferences)
        defer { windows.hide(); host.orderOut(nil) }

        let top = NSScreen.screens.first!.frame.maxY
        func ax(_ v:NSView) -> CGRect {
            WeChatOverlayGeometry.appKitRect(host.convertToScreen(v.convert(v.bounds,to:nil)),desktopTop:top)
        }
        guard let layout = WeChatOverlayGeometry(window:ax(root),search:ax(search),list:ax(list)),
              ax(search).contains(layout.button), !layout.button.intersects(layout.tint),
              WeChatOverlayGeometry(window:ax(root),search:ax(search),list:ax(search)) == nil else {
            throw PackpierError.message("Incorrect overlay bounds")
        }
        windows.show(layout,desktopTop:top,above:host.windowNumber)
        guard let slot = windows.control.contentView as? NSStackView, let button = slot.arrangedSubviews.first as? NSButton,
              let menu = button.menu, windows.control.isVisible, !windows.tint.isVisible else {
            throw PackpierError.message("Default mode must show only the chooser")
        }
        menu.performActionForItem(at:1)
        guard windows.tint.isVisible, windows.tint.ignoresMouseEvents, !windows.control.ignoresMouseEvents,
              windows.tint.frame == host.convertToScreen(list.convert(list.bounds,to:nil)),
              windows.control.styleMask.contains(.nonactivatingPanel) else {
            throw PackpierError.message("Incorrect panel state or coverage")
        }
        // Exercise the original controls separately from the window-level passthrough flag.
        guard host.makeFirstResponder(search), let editor = search.currentEditor() as? NSTextView else {
            throw PackpierError.message("Search could not become first responder")
        }
        editor.insertText("sample",replacementRange:NSRange(location:0,length:0))
        row.performClick(nil)
        let clip = list.contentView
        let initialY = clip.bounds.minY
        clip.scroll(to:NSPoint(x:0,y:initialY == 0 ? 120 : 0))
        list.reflectScrolledClipView(clip)
        guard editor.string == "sample",row.state == .on,clip.bounds.minY != initialY else {
            throw PackpierError.message("Synthetic conversation controls failed")
        }
        let oldFrame = windows.control.frame
        host.setFrameOrigin(NSPoint(x:host.frame.minX+35,y:host.frame.minY+20))
        guard let moved = WeChatOverlayGeometry(window:ax(root),search:ax(search),list:ax(list)) else {
            throw PackpierError.message("Missing layout after move")
        }
        windows.show(moved,desktopTop:top,above:host.windowNumber)
        guard windows.control.frame == oldFrame.offsetBy(dx:35,dy:20) else {
            throw PackpierError.message("Button did not follow the host")
        }
        menu.performActionForItem(at:0)
        guard !windows.tint.isVisible,windows.control.isVisible,menu.items[0].state == .on else {
            throw PackpierError.message("Restoring WeChat default left a tint")
        }
        windows.hide()
        guard !windows.control.isVisible && !windows.tint.isVisible else { throw PackpierError.message("Overlay still visible") }
        print("PASS isolated AppKit fixture: default → celadon → default, click-through flag, search edit, row action, scroll bounds, window movement and teardown")
    }
}
