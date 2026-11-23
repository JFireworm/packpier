import AppKit
import ServiceManagement
import SwiftUI

@MainActor enum NativeUI {
    static func checkLoginItemRetry() throws {
        let suite = "packpier-login-test-" + UUID().uuidString
        let prefs = UserDefaults(suiteName:suite)!
        defer { prefs.removePersistentDomain(forName:suite) }
        var attempts = 0
        var failRegistration = true
        func start(_ status: SMAppService.Status, installed: Bool = true) throws {
            try LoginItemDefaults.apply(defaults:prefs, domain:suite, status:status, canRegister:installed) {
                attempts += 1
                if failRegistration { throw CocoaError(.fileWriteNoPermission) }
            }
        }
        prefs.set("en", forKey:"packpier.language")
        try start(.notRegistered, installed:false)
        prefs.set("frame", forKey:"NSWindow Frame manager")
        try start(.notFound)
        guard attempts == 0 else { throw PackpierError.message("Uninstalled app registered as a login item") }
        do {
            try start(.notRegistered)
            throw PackpierError.message("Missing system registration error")
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {}
        failRegistration = false
        try start(.notRegistered)
        try start(.notRegistered)
        guard attempts == 2 else { throw PackpierError.message("Login registration retry or opt-out failed") }
        for status: SMAppService.Status in [.enabled, .requiresApproval] {
            prefs.removePersistentDomain(forName:suite)
            try start(status)
            try start(.notRegistered)
        }
        guard attempts == 2 else { throw PackpierError.message("Repeated a registered login request") }
    }

    static func checkTime() throws {
        try checkLoginItemRetry()
        let raw = "2026-11-21T13:33:01.724321Z [INFO] 2024-03-17T12:00:00Z\nnext line\n2026-11-21T02:01:00-05:00 [WARN] ok"
        let china = LogTimestamps.display(raw,in:TimeZone(identifier:"Asia/Shanghai")!)
        guard china == "2026-11-21 21:33:01.724 [INFO] 2024-03-17T12:00:00Z\nnext line\n2026-11-21 15:01:00 [WARN] ok" else { throw PackpierError.message(china) }
        let dst = LogTimestamps.display("2026-03-08T06:59:59Z a\n2026-03-08T07:00:00Z b",in:TimeZone(identifier:"America/New_York")!)
        guard dst == "2026-03-08 01:59:59 a\n2026-03-08 03:00:00 b" else { throw PackpierError.message(dst) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        guard ShellLogBlock.copy(raw,in:TimeZone(identifier:"Asia/Shanghai")!,to:board),
              board.string(forType:.string) == china,
              !ShellLogBlock.copy("",in:.current,to:board),
              board.string(forType:.string) == china else { throw PackpierError.message("Log preview clipboard mismatch") }
        let suite = "packpier-updates-test-" + UUID().uuidString
        let prefs = UserDefaults(suiteName:suite)!
        defer { prefs.removePersistentDomain(forName:suite) }
        var registrations = 0
        func launch(_ domain: String, _ preferences: UserDefaults) throws {
            try LoginItemDefaults.apply(defaults: preferences, domain: domain, status: .notRegistered) { registrations += 1 }
        }
        try launch(suite, prefs)
        guard registrations == 1 else { throw PackpierError.message("Fresh installation skipped login registration") }
        try launch(suite, prefs)
        guard registrations == 1 else { throw PackpierError.message("Login item registered again after being disabled") }
        let legacy = suite + "-upgrade"
        let legacyPrefs = UserDefaults(suiteName:legacy)!
        defer { legacyPrefs.removePersistentDomain(forName:legacy) }
        legacyPrefs.set("frame", forKey:"NSWindow Frame manager")
        try launch(legacy, legacyPrefs)
        guard registrations == 1 else { throw PackpierError.message("Upgrade replaced the existing login item preference") }

        let updates = AppUpdates(bundle:.main,defaults:prefs)
        guard updates.automatic else { throw PackpierError.message("Automatic updates should default to on") }
        updates.setAutomatic(false)
        guard !AppUpdates(bundle:.main,defaults:prefs).automatic else { throw PackpierError.message("Automatic updates opt-out lost") }
        updates.setAutomatic(true)
        let next = AppUpdates(bundle:.main,defaults:prefs)
        next.check()
        guard next.automatic, !next.configured, AppUpdates.homepage.absoluteString == "https://github.com/JFireworm/packpier", !next.notice.isEmpty else {
            throw PackpierError.message("Update configuration and saved preference mismatch")
        }
        if let path = ProcessInfo.processInfo.environment["PACKPIER_TEST_APP"], let bundle = Bundle(path:path) {
            let codes = PPText.languages.map(\.code)
            guard Set(codes) == Set(bundle.localizations),
                  PPText.resolved("system",preferred:["ja-JP"]) == "ja",
                  PPText.resolved("system",preferred:["ko-KR"]) == "ko" else {
                throw PackpierError.message("Supported display languages do not match the app bundle")
            }
            let market = try Marketplace(directory:bundle.resourceURL!.appendingPathComponent("Marketplace"))
            for code in codes {
                guard PPText.resolved(code,preferred:["en-US"]) == code,
                      market.entries.allSatisfy({ $0.source?.absoluteString.hasPrefix(AppUpdates.homepage.absoluteString + "/tree/main/") == true && $0.name[code]?.isEmpty == false && $0.summary[code]?.isEmpty == false }) else {
                    throw PackpierError.message("Missing display language or catalog translation: " + code)
                }
            }
            try AuthorSkill.copy(from:bundle,to:board)
            let canonical = try String(contentsOfFile:"Resources/Skills/packpier-plugin-author/SKILL.md",encoding:.utf8)
            guard board.string(forType:.string) == canonical else { throw PackpierError.message("Packaged skill mismatch") }
            print("PASS bundled Skill copied verbatim to private pasteboard")
        }
        print("PASS code-block copy matches visible timestamps and preserves the clipboard on empty input")
        print("PASS local log dates, fractional seconds, numeric offsets, daylight saving and original message")
    }

    static func checkDrag(_ m: Manager) async throws {
        let window = NSWindow(contentRect:NSRect(x:60,y:60,width:1060,height:850),styleMask:[.titled],backing:.buffered,defer:false)
        let drag = PackageDrag()
        let host = NSHostingView(rootView:Dashboard(m:m,drag:drag))
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        func settle() async throws {
            try await Task.sleep(nanoseconds:60_000_000)
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        func grips(_ view:NSView) -> [GripView] {
            (view as? GripView).map { [$0] } ?? view.subviews.flatMap(grips)
        }
        var counter = 0
        func send(_ type:NSEvent.EventType,_ point:NSPoint) {
            counter += 1
            let event = NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                windowNumber:window.windowNumber,context:nil,eventNumber:counter,clickCount:1,pressure:type == .leftMouseUp ? 0 : 1)!
            NSApp.sendEvent(event)
        }
        func gesture(from id:String,to target:String,after:Bool, cancel:Bool=false) async throws {
            try await settle()
            guard let grip = grips(host).first(where:{$0.packageID == id}), let row = drag.rows.allObjects.first(where:{$0.packageID == target}) else {
                throw PackpierError.message("Native grip or target missing")
            }
            let start = grip.convert(NSPoint(x:grip.bounds.midX,y:grip.bounds.midY),to:nil)
            let rect = row.convert(row.bounds,to:nil)
            let end = NSPoint(x:rect.midX,y:after ? rect.minY+8 : rect.maxY-8)
            let hit = host.hitTest(host.superview!.convert(start,from:nil))
            guard hit === grip else { throw PackpierError.message("Wrong hit view") }
            let previous = m.state.packages.map(\.id)
            send(.leftMouseDown,start)
            send(.leftMouseDragged,NSPoint(x:start.x+4,y:start.y))
            send(.leftMouseDragged,end)
            try await settle()
            guard drag.source == id, drag.slot == .init(id:target,after:after),
                  m.state.packages.map(\.id) == previous else {
                throw PackpierError.message("Drag tracking failed · \(drag.source ?? "nil") · \(String(describing:drag.slot))")
            }
            if cancel {
                let escape = NSEvent.keyEvent(with:.keyDown,location:end,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:window.windowNumber,context:nil,characters:"\u{1B}",charactersIgnoringModifiers:"\u{1B}",isARepeat:false,keyCode:53)!
                NSApp.sendEvent(escape)
            }
            send(.leftMouseUp,end)
            try await settle()
            guard drag.source == nil, drag.slot == nil else { throw PackpierError.message("Drag feedback did not clear") }
            if cancel {
                guard m.state.packages.map(\.id) == previous else { throw PackpierError.message("Escape committed load order") }
            } else {
                let expected = try PackageOrder(previous.map{TweakPackage(fields:["id":$0])},moving:id,to:target,after:after).ids
                let deadline = ContinuousClock.now + .seconds(5)
                while m.ordering && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
                guard !m.ordering, m.state.packages.map(\.id) == expected else {
                    throw PackpierError.message("鼠标松开后未保存顺序")
                }
            }
        }
        try await gesture(from:"prism",to:"ct-a",after:false,cancel:true)
        try await gesture(from:"prism",to:"ct-a",after:false)
        try await gesture(from:"prism",to:"ct-c",after:true)
        print("PASS native NSWindow hit test → mouseDown → mouseDragged → insertion feedback → mouseUp → official loader; both directions and Escape")
    }
}
