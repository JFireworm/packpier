import SwiftUI

@MainActor final class UpdateFailureLogger: NSObject, SPUUpdaterDelegate {
    private let log: ConnectionLog

    init(log: ConnectionLog) { self.log = log }

    // Sparkle delivers the wrapped download error here too, so one callback covers the failure once.
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        record(error)
    }

    func record(_ error: Error) {
        if let message = Self.summary(error as NSError) { try? log.append(message) }
    }

    static func summary(_ error: NSError) -> String? {
        let normalSparkleCodes = [SUNoUpdateError, SUInstallationCanceledError, SUInstallationAuthorizeLaterError]
        if error.domain == SUSparkleErrorDomain && normalSparkleCodes.contains(where: { Int($0) == error.code }) { return nil }
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return nil }

        var codes: [String] = []
        var host: String?
        var next: NSError? = error
        for _ in 0..<8 {
            guard let current = next else { break }
            let domain = current.domain.range(of: #"^[A-Za-z0-9_.-]{1,128}$"#, options: .regularExpression) == nil
                ? "<redacted>" : current.domain
            codes.append("\(domain)/\(current.code)")
            host = failingHost(current) ?? host
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let chain = codes.joined(separator: " → ")
        return "Sparkle update failed · \(chain)" + (host.map { " · host=\($0)" } ?? "")
    }

    private static func failingHost(_ error: NSError) -> String? {
        for key in [NSURLErrorFailingURLErrorKey, NSURLErrorFailingURLStringErrorKey] {
            let value = error.userInfo[key]
            let url = value as? URL ?? (value as? String).flatMap { URL(string: $0) }
            if let scheme = url?.scheme?.lowercased(), ["http", "https"].contains(scheme),
               let host = url?.host?.lowercased(),
               host.range(of: #"^[a-z0-9.\-:\[\]]{1,253}$"#, options: .regularExpression) != nil {
                return host
            }
        }
        return nil
    }
}

@MainActor final class AppUpdates: ObservableObject {
    static let shared = AppUpdates()
    @Published private(set) var available = false
    @Published private(set) var notice = ""
    @Published private(set) var automatic: Bool
    static let homepage = URL(string:"https://github.com/JFireworm/packpier")!
    private let defaults: UserDefaults
    private let failureLogger = UpdateFailureLogger(log: ConnectionLog())
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
        let control = SPUStandardUpdaterController(starting:false,delegate:failureLogger,driver:nil)
        controller = control
        do {
            try control.updater.start()
            applyPreference()
            observation = control.updater.observe(\.canCheckForUpdates,options:[.initial,.new]) { [weak self] updater,_ in
                let ready = updater.canCheckForUpdates
                Task { @MainActor [weak self] in self?.available = ready }
            }
        } catch {
            failureLogger.record(error)
            notice = "更新服务启动失败"
        }
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
