import AppKit
import SwiftUI

enum PackageTarget: String, Codable, CaseIterable { case codex, wechat, feishu }

@MainActor struct WeChatLauncher: View {
    private static let bundleID = "com.tencent.xinWeChat"
    @State private var url: URL?
    @State private var version = ""
    @State private var running = false
    @State private var opening = false
    @State private var launchError: String?

    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                if let url {
                    Image(nsImage:NSWorkspace.shared.icon(forFile:url.path))
                        .resizable().frame(width:32,height:32).accessibilityHidden(true)
                    VStack(alignment:.leading) {
                        Text(verbatim:"\(PPText.get("微信")) \(version)").font(.headline)
                        Text(LocalizedStringKey(running ? "运行中" : "已安装")).foregroundStyle(.secondary)
                    }
                } else { Text("微信未安装").foregroundStyle(.secondary) }
                Spacer()
                if Bundle.main.object(forInfoDictionaryKey:"PackpierWeChatTestMode") as? Bool != true {
                Button("打开微信",systemImage:"arrow.up.forward.app") { openWeChat() }
                    .disabled(url == nil || opening)
                }
            }
            WeChatOverlaySettings()
            if let launchError { Text(launchError).font(.callout).foregroundStyle(.red) }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for:NSWorkspace.didLaunchApplicationNotification)
            .merge(with:NSWorkspace.shared.notificationCenter.publisher(for:NSWorkspace.didTerminateApplicationNotification))) { event in
            if (event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Self.bundleID { refresh() }
        }
    }

    private func refresh() {
        let installed = WeChatOverlayTarget.installedURL
        if WeChatOverlayTarget.testMode { url = WeChatOverlay.shared.copy?.url }
        else if FileManager.default.fileExists(atPath:installed.path) { url = installed }
        else { url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:Self.bundleID) }
        version = url.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""
        running = NSRunningApplication.runningApplications(withBundleIdentifier:Self.bundleID).contains { !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath().path == url?.resolvingSymlinksInPath().path }
    }

    private func openWeChat() {
        refresh()
        guard let url else { return }
        opening = true
        launchError = nil
        NSWorkspace.shared.openApplication(at:url,configuration:.init()) { _, error in
            DispatchQueue.main.async {
                opening = false
                launchError = error?.localizedDescription
                refresh()
            }
        }
    }
}
