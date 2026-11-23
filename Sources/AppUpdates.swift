import SwiftUI

@MainActor final class AppUpdates: ObservableObject {
    static let shared = AppUpdates()
    @Published private(set) var available = false
    @Published private(set) var notice = ""
    @Published private(set) var automatic: Bool
    static let homepage = URL(string:"https://github.com/JFireworm/packpier")!
    private let defaults: UserDefaults
    private let controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    static func httpsURL(_ value: Any?) -> URL? {
        guard let string = value as? String, let url = URL(string:string),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults:["packpier.automaticUpdates": true])
        automatic = defaults.bool(forKey:"packpier.automaticUpdates")
        guard Self.httpsURL(bundle.object(forInfoDictionaryKey:"SUFeedURL")) != nil,
              let key = bundle.object(forInfoDictionaryKey:"SUPublicEDKey") as? String,
              Data(base64Encoded:key)?.count == 32 else {
            controller = nil
            return
        }
        let control = SPUStandardUpdaterController(starting:false,delegate:nil,driver:nil)
        controller = control
        do {
            try control.updater.start()
            applyPreference()
            observation = control.updater.observe(\.canCheckForUpdates,options:[.initial,.new]) { [weak self] updater,_ in
                let ready = updater.canCheckForUpdates
                Task { @MainActor [weak self] in self?.available = ready }
            }
        } catch { notice = "更新服务启动失败" }
    }

    func setAutomatic(_ enabled: Bool) {
        automatic = enabled
        defaults.set(enabled,forKey:"packpier.automaticUpdates")
        applyPreference()
    }
    private func applyPreference() {
        controller?.updater.automaticallyChecksForUpdates = automatic
        controller?.updater.automaticallyDownloadsUpdates = automatic
    }
    var configured: Bool { controller != nil }
    func check() {
        guard let updater = controller?.updater else {
            notice = "更新源待公布，当前无法查询新版本。"
            return
        }
        if updater.canCheckForUpdates { updater.checkForUpdates() }
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updates = AppUpdates.shared
    var body: some View {
        Button("检查更新",systemImage:"arrow.clockwise") { updates.check() }
            .disabled(updates.configured && !updates.available)
    }
}

struct UpdateSettings: View {
    @ObservedObject var updates = AppUpdates.shared
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("自动更新")
                Spacer()
                Toggle("自动更新",isOn:Binding(get:{ updates.automatic },set:updates.setAutomatic))
                    .labelsHidden().toggleStyle(.switch)
            }
            Text(LocalizedStringKey(updates.configured ? "自动检查并下载签名版本，由系统更新器完成安装。" : "更新源待公布。自动更新偏好会保存在本机。"))
                .font(.callout).foregroundStyle(.secondary)
            if !updates.notice.isEmpty { Text(LocalizedStringKey(updates.notice)).font(.callout) }
        }
    }
}
