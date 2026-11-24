import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class Manager: ObservableObject {
    @Published var state = HostState()
    @Published var connection = "正在连接加载器"
    @Published private(set) var restartMessage: String?
    @Published private(set) var restartStartedAt: TimeInterval?
    @Published private var restartTask: Task<Void, Never>?
    var isRestartingCodex: Bool { restartTask != nil }
    var canRestartCodex: Bool {
        target == .codex && state.ready && state.enabled && !state.connected && !externalLoaderRunning &&
            !loaderConflict && state.status != "error" && !isRestartingCodex &&
            (restartMessage != nil || connection == CodexListener.Status.missing.rawValue)
    }
    @Published private(set) var externalLoaderRunning = false
    @Published private var waitingForOtherLoader = false
    var loaderConflict: Bool { waitingForOtherLoader || state.status == "loaderConflict" }
    @Published private var releaseWatchdog: Task<Void, Never>?
    var switchingLoader: Bool { releaseWatchdog != nil }
    @Published var error: String?
    @Published var notice = ""
    @Published var preview: LocalPackage?
    @Published var choosing = false
    @Published var authorization: Authorization?
    @Published var page = "插件市场"
    @Published var selectedPackageID: String?
    private let connectionLog: ConnectionLog
    private var lastHostReport = ""

    init(connectionLog: ConnectionLog = ConnectionLog()) {
        self.connectionLog = connectionLog
    }

    private func record(_ message: String) {
        do { try connectionLog.append(message) }
        catch { NSLog("Packpier connection log: %@", error.localizedDescription) }
    }
    #if PACKPIER_INDEPENDENT
    private let codexStartup = CodexStartup()
    private func observeCodexStartup() {
        guard !terminating, !isRestartingCodex, state.ready, state.enabled,
              target == .codex, state.status != "loaderConflict" else {
            codexStartup.stop()
            return
        }
        if waitingForCodex { connection = codexStartup.message }
        codexStartup.start { [weak self] message in
            guard let self else { return }
            self.record("Codex: " + message)
            if self.waitingForCodex { self.connection = message }
        }
    }
    private var waitingForCodex: Bool {
        state.status == "checkingHost" || state.status == "waitingForCDP"
    }
    #endif
    let target: PackageTarget = WeChatOverlayTarget.testMode ? .wechat : .codex

    @Published private(set) var exportingID: String?
    private var exportStarted = false
    @Published var search = ""
    @Published private(set) var ordering = false
    private var replies: [Int: CheckedContinuation<Fields, Error>] = [:]
    private var loader: Loader?
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []
    private var initializing: Int?
    private var pending: [Int:String] = [:]
    private var importInFlight: LocalPackage?
    private var launchImport: URL?
    private var awaitingTrust: String?
    func addFromCommandLine(_ url: URL) {
        launchImport = url
        beginLaunchImportIfReady()
    }
    private func beginLaunchImportIfReady() {
        guard state.ready, let url = launchImport, !installing else { return }
        launchImport = nil
        readFile(url, confirm:true)
    }
    private var blockedByExternalLoader = false
    private var terminating = false
    private var onStopped: (() -> Void)?

    struct Authorization: Identifiable {
        let id = UUID()
        let packageID: String
        let version: String
        let token: String
        let reason: String
    }
    private var official: [NSRunningApplication] {
        #if PACKPIER_INDEPENDENT
        return []
        #else
        return NSRunningApplication.runningApplications(withBundleIdentifier:"com.zgccrui.CodexTweaks").filter { !$0.isTerminated }
        #endif
    }
    func begin() {
        guard observers.isEmpty else { return }
        let info = Bundle.main.infoDictionary
        record("Packpier \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName:name, object:nil, queue:.main) { [weak self] event in
                guard let app = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.zgccrui.CodexTweaks" else { return }
                MainActor.assumeIsolated { self?.reconcile() }
            })
        }
        reconcile()
    }
    func reconcile() {
        guard !terminating else { return }
        externalLoaderRunning = !official.isEmpty
        if externalLoaderRunning {
            connection = switchingLoader ? "等待原加载器退出" : "另一个加载器正在使用 Codex"
            state = HostState()
            if loader != nil { blockedByExternalLoader = true }
            loader?.close()
        } else {
            releaseWatchdog?.cancel()
            releaseWatchdog = nil
            if loader == nil {
                #if PACKPIER_INDEPENDENT
                let conflict = LoaderConflict.running()
                if conflict {
                    if !waitingForOtherLoader { record("另一个加载器正在运行") }
                    connection = "另一个加载器正在运行"
                    waitingForOtherLoader = true
                    return
                }
                waitingForOtherLoader = false
                #endif
                openLoader()
            }
        }
    }
    func reconnectFromMarketplace() {
        guard !terminating, !switchingLoader else { return }
        let owners = official
        guard !owners.isEmpty else { reconcile(); return }
        // Only a deliberate user action asks the other manager to quit.
        for owner in owners where !owner.terminate() && !owner.isTerminated {
            error = "原管理器未能正常退出，请关闭它后重试。"
            return
        }
        connection = "等待原加载器退出"
        releaseWatchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard let self, !terminating else { return }
            releaseWatchdog = nil
            if !official.isEmpty { error = "原管理器未能正常退出，请关闭它后重试。" }
            reconcile()
        }
        reconcile()
    }
    func restartCodex() {
        guard canRestartCodex, !terminating else { return }
        let ticket = generation
        #if PACKPIER_INDEPENDENT
        codexStartup.pauseForRestart()
        #endif
        restartStartedAt = ProcessInfo.processInfo.systemUptime
        restartMessage = "正在等待 Codex 退出…"
        restartTask = Task {
            defer {
                if generation == ticket {
                    restartTask = nil
                    restartStartedAt = nil
                    #if PACKPIER_INDEPENDENT
                    codexStartup.resumeAfterRestart()
                    observeCodexStartup()
                    #endif
                }
            }
            do {
                try await CodexStartup.restart { message in
                    restartMessage = message
                    record("Codex: " + message)
                }
                let deadline = ProcessInfo.processInfo.systemUptime + 50
                while !state.connected {
                    try Task.checkCancellation()
                    if state.status == "error" || state.status == "loaderConflict" {
                        let detail = (state.raw["status"] as? Fields)?["message"] as? String ?? connection
                        throw PackpierError.message(detail)
                    }
                    guard ProcessInfo.processInfo.systemUptime < deadline else {
                        throw PackpierError.message("Codex 已重新打开，窗口仍未连接。")
                    }
                    try await Task.sleep(for: .milliseconds(250))
                }
                restartMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                restartMessage = error.localizedDescription
            }
            if let restartMessage { record("Codex: " + restartMessage) }
        }
    }
    private func reconcileAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds:700_000_000)
            reconcile()
        }
    }
    private func openLoader() {
        do {
            let host = try HostLocation.bundled()
            #if PACKPIER_INDEPENDENT
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: false)
            let params: Fields = ["libraryDirectory": support.appendingPathComponent("Packpier/PluginLibrary").path,
                                  "bundledPackagesDirectory": host.resources.appendingPathComponent("BundledPlugins").path]
            try startSession(executable: host.executable, params: params, environment: ProcessInfo.processInfo.environment)
            #else
            // An exiting GUI can disappear from NSWorkspace before its helper releases the state.
            let check = Process()
            check.executableURL = URL(fileURLWithPath:"/usr/bin/pgrep")
            check.arguments = ["-f",#"^/Applications/Codex Tweaks\.app/Contents/Resources/codex-tweaks-backend($| )"#]
            check.standardOutput = FileHandle.nullDevice
            try check.run()
            check.waitUntilExit()
            if check.terminationStatus == 0 {
                connection = "等待原加载器退出"
                reconcileAfterDelay()
                return
            }
            guard check.terminationStatus == 1 else { throw PackpierError.message("无法确认加载器占用状态。") }
            let fm = FileManager.default
            let support = try fm.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:false)
            let cache = try fm.url(for:.cachesDirectory,in:.userDomainMask,appropriateFor:nil,create:false)
            try BuiltInPackages.prepare(resources:host.resources, support:support)
            builtInBuilds.removeAll()
            managesBuiltIns = true
            var environment = ProcessInfo.processInfo.environment
            // Reuse the installed compiler when npm has it; normal npm fallback works on a fresh machine.
            environment["npm_config_prefer_offline"] = "true"
            try startSession(executable:host.executable, params:host.parameters(support:support,cache:cache), environment:environment)
            #endif
        } catch {
            self.error = error.localizedDescription
            record("Loader startup failed: " + error.localizedDescription)
            connection = "加载器未连接"
            if loader?.process.isRunning == true { loader?.close() } else { loader = nil }
        }
    }
    func startSession(executable: URL, arguments: [String] = [], params: Fields, environment: [String:String]) throws {
        guard loader == nil else { throw PackpierError.message("加载器正在运行。") }
        blockedByExternalLoader = false
        let ticket = UUID()
        generation = ticket
        let hostClient = Loader(receive: { [weak self] msg in
            guard self?.generation == ticket else { return }
            self?.receive(msg)
        }, ended: { [weak self] in self?.didStop(ticket) })
        try hostClient.start(executable:executable, arguments:arguments, environment:environment)
        lastHostReport = ""
        record("Loader started · pid=\(hostClient.process.processIdentifier)")
        loader = hostClient
        initializing = try hostClient.request("initialize",params)
        connection = "正在连接加载器"
    }
    private func didStop(_ ticket: UUID) {
        guard generation == ticket else { return }
        restartTask?.cancel()
        restartTask = nil
        restartMessage = nil
        restartStartedAt = nil
        record("Loader stopped · status=\(loader?.process.terminationStatus ?? -1)")
        #if PACKPIER_INDEPENDENT
        codexStartup.resumeAfterRestart()
        codexStartup.stop()
        #endif
        loader = nil
        for waiter in replies.values { waiter.resume(throwing:PackpierError.message("加载器连接已结束。")) }
        replies.removeAll()
        state = HostState()
        if exportingID != nil && !terminating { error = "加载器已断开，请检查目标 ZIP。" }
        exportingID = nil
        exportStarted = false
        importInFlight = nil
        pending.removeAll()
        initializing = nil
        if terminating { onStopped?(); return }
        if !official.isEmpty { externalLoaderRunning = true; connection = "另一个加载器正在使用 Codex" }
        else if blockedByExternalLoader || LoaderConflict.running() { reconcile() }
        else { connection = "加载器已退出，可重新连接" }
    }
    func finish(_ callback: @escaping () -> Void) {
        terminating = true
        restartTask?.cancel()
        #if PACKPIER_INDEPENDENT
        codexStartup.stop()
        #endif
        releaseWatchdog?.cancel()
        onStopped = callback
        if let loader { loader.close() } else { callback() }
    }
    private func receive(_ msg: Fields) {
        if terminating || externalLoaderRunning { return }
        if let id = msg["id"] as? Int {
            if let waiter = replies.removeValue(forKey:id) {
                if let error = msg["error"] as? Fields {
                    waiter.resume(throwing:PackpierError.message(error["message"] as? String ?? "加载器操作失败"))
                } else { waiter.resume(returning:msg["result"] as? Fields ?? [:]) }
                return
            }
            let operation = pending.removeValue(forKey:id)
            if let failure = msg["error"] as? Fields {
                error = failure["message"] as? String ?? "操作失败"
                if operation == "installLocalPackage" { importInFlight = nil }
                if operation == "exportPackage" { exportingID = nil; exportStarted = false }
                if id == initializing {
                    record("Loader initialization failed: " + (error ?? "unknown"))
                    loader?.close()
                }
                return
            }
            #if PACKPIER_INDEPENDENT
            if operation == "exportPackage" { exportingID = nil; exportStarted = false }
            if operation == "installLocalPackage", let file = importInFlight {
                importInFlight = nil
                notice = PPText.format("%@ 已添加。", file.name)
            }
            if operation != nil, let raw = msg["result"] as? Fields, raw["packages"] != nil { update(raw) }
            #endif
            if id == initializing, let raw = msg["result"] as? Fields {
                initializing = nil
                update(raw)
            }
        } else if msg["event"] as? String == "state", let raw = msg["data"] as? Fields { update(raw) }
    }
    private var managesBuiltIns = false
    private var builtInBuilds = Set<String>()
    private func prepareBuiltInBuilds() {
        guard managesBuiltIns, state.ready, state.enabled else { return }
        for p in state.packages where BuiltInPackages.ids.contains(p.id) {
            guard state.hasEnabled(p.id), !p.builtCurrent, !state.building(p.id), p.canBuild,
                  p.id == BuiltInPackages.sign || !p.hasBuild,
                  builtInBuilds.insert(p.id + "@" + p.version).inserted else { continue }
            send("buildPackage", ["packageID":p.id])
        }
    }
    private func update(_ raw: Fields) {
        state = HostState(raw:raw)
        if !isRestartingCodex && (state.connected || !state.enabled) { restartMessage = nil }
        let detail = (raw["status"] as? Fields)?["message"] as? String ?? ""
        let hostReport = "Loader responded · window=\(state.status) \(detail)"
        if hostReport != lastHostReport {
            record(hostReport)
            lastHostReport = hostReport
        }
        prepareBuiltInBuilds()
        if let id = exportingID {
            if (raw["exportingPackageIDs"] as? [String] ?? []).contains(id) {
                exportStarted = true
            } else if exportStarted {
                if let failure = raw["localOperationError"] as? String { error = failure }
                else if let message = raw["localOperationMessage"] as? String { notice = message }
                exportingID = nil
                exportStarted = false
            }
        }
        let texts = ["waitingForHost":"等待 Codex 窗口接入","connected":"加载器已连接","waitingForCDP":"等待 Codex 连接","waitingForPage":"等待 Codex 页面",
                     "starting":"正在连接 Codex","disabled":"加载器已暂停","codexNotRunning":"Codex 未运行",
                     "restartRequired":"当前 Codex 未开启插件连接端口，需要重启 Codex。","launchingCodex":"正在连接 Codex","error":"接管窗口失败",
                     "loaderConflict":"另一个加载器正在运行",
                     "nodeMissing":"内置运行环境缺失，请重新安装 Packpier。"]
        connection = texts[state.status] ?? "等待加载器状态"
        #if PACKPIER_INDEPENDENT
        observeCodexStartup()
        #endif
        beginLaunchImportIfReady()
        if let id = awaitingTrust, let p = state.packages.first(where: { $0.id == id }),
           state.hasEnabled(id), !state.building(id), p.canAuthorize {
            awaitingTrust = nil
            requestTrust(p)
        }
        if let file = importInFlight {
            if let failure = raw["localOperationError"] as? String, !failure.isEmpty {
                error = failure
                importInFlight = nil
            } else if raw["installingLocalPackage"] as? Bool != true, raw["localOperationMessage"] is String,
                      let installed = state.packages.first(where: { $0.id == file.name && $0.version == file.version }) {
                importInFlight = nil
                notice = PPText.format("%@ 已添加。",installed.title)
                activate(installed)
            }
        }
    }
    func send(_ method: String, _ params: Fields = [:]) {
        do {
            guard let loader, state.ready, !externalLoaderRunning else { throw PackpierError.message("请先连接 Codex 加载器。") }
            pending[try loader.request(method,params)] = method
        } catch {
            if method == "exportPackage" { exportingID = nil; exportStarted = false }
            if method == "installLocalPackage" { importInFlight = nil }
            self.error = error.localizedDescription
        }
    }
    private func rpc(_ method: String, _ params: Fields = [:]) async throws -> Fields {
        guard let loader, state.ready, !externalLoaderRunning, !terminating else {
            throw PackpierError.message("加载器连接已结束。")
        }
        return try await withCheckedThrowingContinuation { waiter in
            do { replies[try loader.request(method,params)] = waiter }
            catch { waiter.resume(throwing:error) }
        }
    }

    func movePackage(_ id: String, to target: String, after: Bool) async {
        guard !ordering, state.ready, !externalLoaderRunning, id != target else { return }
        ordering = true
        defer { ordering = false }
        let ticket = generation
        do {
            let current = HostState(raw: try await rpc("getState"))
            let plan = try PackageOrder(current.packages, moving: id, to: target, after: after)
            guard generation == ticket, plan.ids != current.packages.map(\.id) else { return }
            let result = try await rpc("setPackageOrder", ["packageIDs": plan.ids])
            guard generation == ticket else { return }
            update(result)
        } catch {
            if generation == ticket { self.error = error.localizedDescription }
        }
    }

    func logFileForReveal() throws -> URL {
        try connectionLog.append("Snapshot · loaderResponded=\(state.ready) window=\(state.status) · \(connection)")
        return connectionLog.url
    }

    func revealLog() {
        do {
            let file = try logFileForReveal()
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            self.error = "\(connectionLog.url.path)\n\(error.localizedDescription)"
        }
    }
    func chooseFile() {
        guard target == .codex else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.zip]
        picker.prompt = PPText.get("查看插件包")
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            if result == .OK, let url = picker.url { self?.readFile(url) }
        }
        if let window = NSApp.keyWindow { picker.beginSheetModal(for:window,completionHandler:completion) }
        else { picker.begin(completionHandler:completion) }
    }
    func showInstalled(for app: PackageTarget, matching id: String = "") {
        guard app == target else { return }
        search = ""
        selectedPackageID = id.isEmpty ? nil : id
        page = "插件市场"
    }

    func prepareMarketInstall(_ entry: MarketPackage, from market: Marketplace) {
        guard entry.app == .codex, target == .codex, state.ready, !externalLoaderRunning, !transferBusy else { return }
        readFile(market.archive(for:entry), expected:entry)
    }

    func canRemovePlugin(_ package: TweakPackage) -> Bool {
        target == .codex && state.ready && !externalLoaderRunning && !transferBusy &&
            !BuiltInPackages.ids.contains(package.id) && !state.building(package.id) &&
            package.actions["delete"] as? Bool != false
    }

    func removePlugin(_ id: String) {
        guard let package = state.packages.first(where: { $0.id == id }), canRemovePlugin(package) else { return }
        send("deletePackage", ["packageID": id])
    }

    func canExport(_ p: TweakPackage) -> Bool {
        state.ready && !externalLoaderRunning && !transferBusy && preview == nil && p.actions["export"] as? Bool == true
    }

    func chooseExport(_ p: TweakPackage) {
        guard canExport(p) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = p.fields["exportFileName"] as? String ?? (p.id + "-v" + p.version + ".zip")
        panel.title = PPText.get("导出 ZIP")
        panel.canCreateDirectories = true
        let save: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            if result == .OK, let url = panel.url { self?.exportPackage(p.id,to:url) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for:window,completionHandler:save) }
        else { panel.begin(completionHandler:save) }
    }

    func exportPackage(_ id: String, to url: URL) {
        guard let p = state.packages.first(where:{ $0.id == id }), canExport(p), url.isFileURL else { return }
        exportingID = id
        exportStarted = false
        notice = ""
        send("exportPackage",["packageID":id,"destinationPath":url.path])
    }

    var transferBusy: Bool {
        installing || exportingID != nil || state.raw["installingRemotePackage"] as? Bool == true ||
            !(state.raw["exportingPackageIDs"] as? [String] ?? []).isEmpty ||
            !(state.raw["deletingPackageIDs"] as? [String] ?? []).isEmpty
    }

    func readFile(_ url: URL, confirm: Bool = false, expected: MarketPackage? = nil) {
        guard !transferBusy, preview == nil else { return }
        choosing = true
        Task {
            do {
                let file = try await Task.detached { try LocalPackage(source:url) }.value
                if let expected, file.name != expected.id || file.version != expected.version {
                    throw PackpierError.message("插件文件与市场版本不一致。")
                }
                if expected == nil { page = "插件市场" }
                preview = file
                if confirm && target == .codex { confirmImport() }
            }
            catch { self.error = error.localizedDescription }
            choosing = false
        }
    }
    var installing: Bool { choosing || importInFlight != nil || state.raw["installingLocalPackage"] as? Bool == true }
    func confirmImport() {
        guard let file = preview, state.ready, !externalLoaderRunning, exportingID == nil else { return }
        if let new = PackageIdentifierMigration.names[file.name] {
            error = PPText.format("此内置插件已更名为 %@。请使用插件市场中的版本。",new)
            return
        }
        if let old = state.packages.first(where:{ $0.id == file.name }), old.version != file.version {
            error = PPText.format("已安装 %@ %@。请在插件目录更新源码后重新编译。",old.id,old.version)
            return
        }
        showInstalled(for:.codex,matching:file.name)
        preview = nil
        awaitingTrust = file.name
        if let old = state.packages.first(where: { $0.id == file.name }) {
            notice = PPText.format("已使用本机安装的 %@ %@。",old.title,old.version)
            activate(old)
            if state.hasEnabled(old.id) && old.canAuthorize {
                awaitingTrust = nil
                requestTrust(old)
            }
        } else {
            importInFlight = file
            send("installLocalPackage",["sourcePath":file.url.path])
        }
    }
    func activate(_ p: TweakPackage) {
        if !state.hasEnabled(p.id) { send("setPackageEnabled",["packageID":p.id,"enabled":true]) }
        if state.hasEnabled(p.id) && !state.enabled { notice = "插件包已启用。请在「应用工具」中开启加载器。" }
        if !p.builtCurrent && !state.building(p.id) && p.canBuild { send("buildPackage",["packageID":p.id]) }
    }
    func requestTrust(_ p: TweakPackage) {
        guard p.canAuthorize, let token = p.node["authorizationID"] as? String else { return }
        authorization = Authorization(packageID:p.id,version:p.version,token:token,reason:p.node["reason"] as? String ?? "")
    }
    func confirmTrust(_ approval: Authorization) {
        authorization = nil
        guard let current = state.packages.first(where: { $0.id == approval.packageID }),
              current.canAuthorize, current.node["authorizationID"] as? String == approval.token else {
            error = "插件包已更新，请重新查看当前版本的权限。"; return
        }
        send("authorizeNodePackage",["packageID":approval.packageID,"authorizationID":approval.token])
    }
}
