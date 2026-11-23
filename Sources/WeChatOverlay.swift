import AppKit
import SwiftUI

struct WeChatOverlayTarget {
    let url:URL
    let stagingOwner:uid_t?
    static let id = "com.tencent.xinWeChat"

    var permitted:Bool {
        guard let stagingOwner else { return true }
        return getuid() >= 500 && getuid() < 60000 && getuid() != stagingOwner
    }

    static let testMode = Bundle.main.object(forInfoDictionaryKey:"PackpierWeChatTestMode") as? Bool == true
    static let installedURL = URL(fileURLWithPath:"/Applications/WeChat.app",isDirectory:true)
    static func compatible(_ url:URL) -> Bool {
        guard let bundle = Bundle(url:url) else { return false }
        return bundle.bundleIdentifier == id &&
            bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String == "3.8.7" &&
            bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String == "28249"
    }

    static func find(test:Bool = testMode) -> Self? {
        if !test {
            guard compatible(installedURL) else { return nil }
            return Self(url:installedURL.resolvingSymlinksInPath(),stagingOwner:nil)
        }
        let fm = FileManager.default
        let shared = URL(fileURLWithPath:"/Users/Shared",isDirectory:true)
        let folders:[URL]
        let beside = Bundle.main.bundleURL.deletingLastPathComponent()
        if beside.deletingLastPathComponent().path == shared.path && beside.lastPathComponent.hasPrefix("Packpier-WeChat-3.8.7.") {
            folders = [beside]
        } else {
            folders = (try? fm.contentsOfDirectory(at:shared,includingPropertiesForKeys:nil)) ?? []
        }
        for folder in folders.sorted(by:{ $0.path < $1.path }) where folder.lastPathComponent.hasPrefix("Packpier-WeChat-3.8.7.") {
            let url = folder.appendingPathComponent("WeChat-Test.noindex/WeChat.app")
            guard url.resolvingSymlinksInPath().path == url.path, compatible(url),
                  let attributes = try? fm.attributesOfItem(atPath:folder.path),
                  let owner = attributes[.ownerAccountID] as? NSNumber else { continue }
            return Self(url:url,stagingOwner:owner.uint32Value)
        }
        return nil
    }

    func matches(_ app:NSRunningApplication) -> Bool {
        permitted && app.bundleIdentifier == Self.id && app.bundleURL?.resolvingSymlinksInPath().path == url.path
    }
}

@MainActor final class WeChatOverlay: ObservableObject {
    static let shared = WeChatOverlay()
    let copy = WeChatOverlayTarget.find()
    @Published private(set) var enabled = false
    @Published private(set) var status = ""
    private let key = "wechat.celadon.overlay.enabled"
    private lazy var windows = WeChatOverlayWindows(preferences:.standard)
    private var observer:NSObjectProtocol?
    private var timer:Timer?
    private var reading = false
    private var revision = 0
    private let queue = DispatchQueue(label:"local.packpier.wechat.geometry",qos:.userInitiated)

    func restore() {
        if UserDefaults.standard.bool(forKey:key) { setEnabled(true) }
    }

    func setEnabled(_ value:Bool) {
        guard value != enabled else { return }
        if value {
            guard copy?.permitted == true else { return }
            enabled = true
            if !AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey:"wechat.celadon.prompted") {
                UserDefaults.standard.set(true,forKey:"wechat.celadon.prompted")
                requestAccessibility()
            }
            let center = NSWorkspace.shared.notificationCenter
            observer = center.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.watchForeground() }
            }
            watchForeground()
        } else {
            enabled = false
            if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            observer = nil
            stopWatching()
            status = ""
        }
        UserDefaults.standard.set(value,forKey:key)
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openTestCopy() {
        guard WeChatOverlayTarget.testMode, let copy, copy.permitted else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier:WeChatOverlayTarget.id).filter { !$0.isTerminated }
        if let app = running.first(where:copy.matches) { app.activate(); return }
        guard running.isEmpty else { status = "此账户已运行其他微信，请先退出后打开测试副本。"; return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at:copy.url,configuration:config) { [weak self] app, error in
            Task { @MainActor in
                if let error { self?.status = error.localizedDescription }
                else if app.map(copy.matches) != true { self?.status = "启动的应用与测试副本不匹配。" }
            }
        }
    }

    private func stopWatching() {
        revision += 1
        timer?.invalidate()
        timer = nil
        windows.hide()
    }

    private func watchForeground() {
        stopWatching()
        guard enabled, let copy, let app = NSWorkspace.shared.frontmostApplication, copy.matches(app) else {
            if status.isEmpty || status == "贴窗已就绪" { status = WeChatOverlayTarget.testMode ? "等待微信测试副本进入前台" : "等待微信进入前台" }
            return
        }
        let pid = app.processIdentifier
        tick(pid)
        let clock = Timer(timeInterval:0.45,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(pid) }
        }
        clock.tolerance = 0.08
        RunLoop.main.add(clock,forMode:.common)
        timer = clock
    }

    private func tick(_ pid:pid_t) {
        guard enabled, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier == pid, copy?.matches(front) == true else { stopWatching(); return }
        guard AXIsProcessTrusted() else {
            windows.hide(); report("请为 Packpier 开启辅助功能权限。"); return
        }
        guard !reading else { return }
        reading = true
        let ticket = revision
        queue.async {
            let layout = WeChatWindowLayout.read(pid:pid)
            DispatchQueue.main.async {
                self.reading = false
                guard self.enabled, self.revision == ticket,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                guard let layout, let top = NSScreen.screens.first?.frame.maxY,
                      let id = Self.visibleWindow(pid:pid,frame:layout.frame) else {
                    self.windows.hide()
                    self.report("等待识别消息首页的搜索框和会话列表")
                    return
                }
                self.windows.show(layout.geometry,desktopTop:top,above:id)
                self.report("贴窗已就绪")
            }
        }
    }

    private func report(_ message:String) {
        if status != message { status = message }
    }

    private static func visibleWindow(pid:pid_t,frame:CGRect) -> Int? {
        let options:CGWindowListOption = [.optionOnScreenOnly,.excludeDesktopElements]
        guard let items = CGWindowListCopyWindowInfo(options,kCGNullWindowID) as? [[String:Any]] else { return nil }
        for item in items where item[kCGWindowOwnerPID as String] as? Int32 == pid && item[kCGWindowLayer as String] as? Int == 0 {
            guard let values = item[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation:values) else { continue }
            if abs(rect.minX-frame.minX)<3 && abs(rect.minY-frame.minY)<3 &&
                abs(rect.width-frame.width)<3 && abs(rect.height-frame.height)<3 {
                return item[kCGWindowNumber as String] as? Int
            }
        }
        return nil
    }
}

struct WeChatOverlaySettings:View {
    @ObservedObject private var overlay = WeChatOverlay.shared
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Toggle("青瓷 · 会话列表贴窗",isOn:Binding(get:{overlay.enabled},set:overlay.setEnabled))
                .disabled(overlay.copy?.permitted != true)
            if let copy = overlay.copy, copy.permitted {
                HStack {
                    if WeChatOverlayTarget.testMode { Button("打开微信测试副本") { overlay.openTestCopy() } }
                    if overlay.enabled && !AXIsProcessTrusted() {
                        Button("授权辅助功能") {
                            overlay.requestAccessibility()
                        }
                    }
                }
                if !overlay.status.isEmpty { Text(PPText.get(overlay.status)).foregroundStyle(.secondary) }
            } else {
                Text(LocalizedStringKey(WeChatOverlayTarget.testMode ? (overlay.copy == nil ? "未找到微信 3.8.7 测试副本。" : "请在独立的标准测试账户中启用。") : "需要安装微信 3.8.7（28249）。")).foregroundStyle(.secondary)
            }
        }.font(.callout)
    }
}
