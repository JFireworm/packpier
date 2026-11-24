import SwiftUI

extension PackageTarget {
    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .wechat: return "微信"
        case .feishu: return "飞书"
        }
    }
}

struct MarketPackage: Decodable, Identifiable {
    let id: String
    let app: PackageTarget
    let version: String
    let name: [String: String]
    let summary: [String: String]
    let symbol: String
    let source: URL?
    var builtInCeladon: Bool { app == .wechat && id == "wechat-celadon" }
}

struct Marketplace {
    let entries: [MarketPackage]
    let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        let data = try Data(contentsOf:directory.appendingPathComponent("catalog.json"))
        entries = try JSONDecoder().decode([MarketPackage].self, from:data)
        var identifiers = Set<String>()
        for entry in entries {
            guard entry.id.range(of:#"^[a-z0-9][a-z0-9-]*$"#, options:.regularExpression) != nil,
                  identifiers.insert(entry.id).inserted,
                  !entry.version.isEmpty,
                  (entry.builtInCeladon || FileManager.default.isReadableFile(atPath:archive(for:entry).path)) else {
                throw PackpierError.message("插件市场目录无效。")
            }
        }
    }

    static let bundled = Result {
        guard let url = Bundle.main.resourceURL else { throw PackpierError.message("无法读取插件市场。") }
        return try Marketplace(directory:url.appendingPathComponent("Marketplace",isDirectory:true))
    }

    func packages(for app: PackageTarget?) -> [MarketPackage] {
        entries.filter { app == nil || $0.app == app }
    }

    func archive(for entry: MarketPackage) -> URL {
        directory.appendingPathComponent(entry.id).appendingPathExtension("zip")
    }
}


struct MarketItem: Identifiable {
    let id: String
    let catalog: MarketPackage?
    let installed: TweakPackage?
    var symbol: String { catalog?.symbol ?? "shippingbox" }
    func title(_ language:String) -> String { catalog?.name[language] ?? installed?.title ?? id }
    func summary(_ language:String) -> String { catalog?.summary[language] ?? installed?.detail ?? "" }

    static func list(catalog:[MarketPackage], installed:[TweakPackage]) -> [Self] {
        let entries = Dictionary(uniqueKeysWithValues:catalog.map { ($0.id,$0) })
        let localIDs = Set(installed.map(\.id))
        return installed.map { Self(id:$0.id,catalog:entries[$0.id],installed:$0) } +
            catalog.filter { !localIDs.contains($0.id) }.map { Self(id:$0.id,catalog:$0,installed:nil) }
    }
}

enum MarketHealth: Equatable {
    case running, fault, waiting, disabled, absent, builtIn
    var key:String {
        switch self {
        case .running: return "运行中"
        case .fault: return "运行异常"
        case .waiting: return "等待运行"
        case .disabled: return "已停用"
        case .absent: return "未安装"
        case .builtIn: return "内置"
        }
    }
    var color:Color {
        switch self {
        case .running: return .green
        case .fault: return .red
        case .waiting: return .secondary
        default: return .secondary
        }
    }
    static func current(_ p:TweakPackage, state:HostState, mounted:Set<String>) -> Self {
        guard state.hasEnabled(p.id) else { return .disabled }
        if state.failure(p.id) != nil || p.fields["validationError"] is String || !(p.node["lastError"] as? String ?? "").isEmpty { return .fault }
        if state.enabled && p.node["running"] as? Bool == true { return .running }
        guard state.enabled, state.connected, p.hasBuild, p.builtCurrent, !state.building(p.id),
              !p.canAuthorize, mounted.contains(p.id) else { return .waiting }
        return .running
    }
}

struct MarketStatus: View {
    let health: MarketHealth
    let compact: Bool
    var body: some View {
        HStack(spacing:5) {
            if health != .absent && health != .builtIn {
                if health == .waiting { Circle().strokeBorder(health.color,lineWidth:1).frame(width:7,height:7) }
                else { Circle().fill(health.color).frame(width:7,height:7) }
            }
            if !compact || health == .absent || health == .builtIn { Text(LocalizedStringKey(health.key)).font(.caption) }
        }.foregroundStyle(.secondary).accessibilityLabel(Text(LocalizedStringKey(health.key)))
         .help(LocalizedStringKey(health.key))
    }
}

struct MarketplacePage: View {
    @ObservedObject var m: Manager
    @ObservedObject var drag: PackageDrag
    let target: PackageTarget
    let showConnection: () -> Void
    @AppStorage(PPText.languageKey) private var language = "system"
    @State private var removalCandidate: TweakPackage?
    @State private var confirmingRestart = false
    private var code:String { PPText.resolved(language) }
    private var market:Marketplace? { try? Marketplace.bundled.get() }
    private var installed:[TweakPackage] { target == .codex ? m.state.packages : [] }
    private func health(_ item:MarketItem) -> MarketHealth {
        if item.catalog?.builtInCeladon == true { return .builtIn }
        guard let p = item.installed else { return target == .codex && !m.state.ready ? .waiting : .absent }
        return .current(p,state:m.state,mounted:Set((m.state.raw["windowEffects"] as? Fields)?["mounted"] as? [String] ?? []))
    }
    var body: some View {
        let catalog = market?.packages(for:target) ?? []
        let all = MarketItem.list(catalog:catalog,installed:installed)
        let rows = all.filter { m.search.isEmpty || ($0.title(code) + " " + $0.id).localizedCaseInsensitiveContains(m.search) }
        let selected = rows.first { $0.id == m.selectedPackageID } ?? rows.first
        VStack(alignment:.leading,spacing:12) {
            if target == .codex && !m.state.connected {
                HStack(spacing:8) {
                    Text(LocalizedStringKey(confirmingRestart ? "Codex 将退出并重新打开。请先保存窗口中未提交的内容。" : (m.restartMessage ?? m.connection)))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false, vertical:true)
                    if confirmingRestart && m.canRestartCodex {
                        Button("确认重启") { confirmingRestart = false; m.restartCodex() }.buttonStyle(.link)
                        Button("取消") { confirmingRestart = false }.buttonStyle(.link)
                    } else if m.canRestartCodex {
                        Button("重启并连接") { confirmingRestart = true }
                            .help("Codex 将退出并重新打开。请先保存窗口中未提交的内容。")
                            .accessibilityHint("Codex 将退出并重新打开。请先保存窗口中未提交的内容。")
                            .buttonStyle(.link).accessibilityIdentifier("market.restartCodex")
                    }
                    if !confirmingRestart { Button("连接详情", action:showConnection).buttonStyle(.link) }
                    if !m.state.ready {
                        Button(LocalizedStringKey(m.externalLoaderRunning ? "切换到 Packpier" : "重新连接")) {
                            m.reconnectFromMarketplace()
                        }
                        .disabled(m.switchingLoader)
                        .help(LocalizedStringKey(m.externalLoaderRunning ? "正常退出当前管理器，由 Packpier 继续管理插件。" : "重新连接"))
                        .accessibilityIdentifier("market.reconnect")

                    }
                }.font(.callout)
            }
            if case let .failure(error) = Marketplace.bundled { Text(PPText.get(error.localizedDescription)).foregroundStyle(.secondary) }
            HStack(alignment:.top,spacing:14) {
                VStack(alignment:.leading,spacing:8) {
                    HStack { Text("插件").font(.headline); Spacer(); Text(verbatim:String(rows.count)).font(.caption).foregroundStyle(.secondary) }
                    TextField("搜索插件包",text:$m.search).textFieldStyle(.roundedBorder)
                    VStack(spacing:2) { ForEach(rows) { item in indexRow(item,selected:item.id == selected?.id) } }
                }.padding(9).frame(width:185).packpierCard()
                if let item = selected { detail(item).frame(maxWidth:.infinity,alignment:.leading) }
                else { ContentUnavailableView(LocalizedStringKey(m.search.isEmpty ? "此应用暂无插件包" : "没有匹配的插件包"),systemImage:"shippingbox").frame(maxWidth:.infinity,minHeight:180) }
            }
            if !m.notice.isEmpty { Text(PPText.get(m.notice)).font(.callout).foregroundStyle(.secondary) }
        }.onChange(of:m.canRestartCodex) { _, available in
            if !available { confirmingRestart = false }
        }.onDisappear { confirmingRestart = false }.alert("移除插件？", isPresented: Binding(
            get: { removalCandidate != nil },
            set: { if !$0 { removalCandidate = nil } }
        ), presenting: removalCandidate) { package in
            Button("取消", role: .cancel) {}
            Button("移除插件", role: .destructive) { m.removePlugin(package.id) }
        } message: { package in
            Text(verbatim: PPText.format("将删除本机安装的插件「%@」。", package.title))
        }
    }
    private func indexRow(_ item:MarketItem,selected:Bool) -> some View {
        let status = health(item)
        return HStack(spacing:1) {
            if let p = item.installed { packageGrip(p) }
            Button {
                m.selectedPackageID = item.id
            } label: {
                HStack(spacing:6) {
                    MarketIcon(id:item.id,symbol:item.symbol,size:16)
                    Text(verbatim:item.title(code)).font(.callout.weight(.medium)).lineLimit(2)
                    Spacer(minLength:1)
                    MarketStatus(health:status,compact:true)
                }.padding(.horizontal,5).frame(maxWidth:.infinity,minHeight:36,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
             .accessibilityIdentifier("market.plugin." + item.id)
             .accessibilityLabel(Text(verbatim:item.title(code) + " · " + PPText.get(status.key)))
             .accessibilityAddTraits(selected ? .isSelected : [])
        }.padding(.horizontal,2)
        .background(selected || drag.source == item.id ? Color.accentColor.opacity(0.16) : .clear,in:RoundedRectangle(cornerRadius:7))
        .background { if item.installed != nil { PackageRowRegion(id:item.id,drag:drag) } }
        .overlay(alignment:drag.slot?.after == true ? .bottom : .top) {
            if drag.slot?.id == item.id && drag.source != item.id { Capsule().fill(Color.accentColor).frame(height:3).allowsHitTesting(false) }
        }
    }

    private func detail(_ item:MarketItem) -> some View {
        VStack(alignment:.leading,spacing:13) {
            HStack(spacing:10) {
                MarketIcon(id:item.id,symbol:item.symbol,size:25)
                    .frame(width:42,height:42).background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:10))
                VStack(alignment:.leading,spacing:3) {
                    Text(verbatim:item.title(code)).font(.title2.bold())
                    Text(verbatim:PPText.get(target.displayName)+" · v"+(item.installed?.version ?? item.catalog?.version ?? "—")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let p = item.installed {
                    Toggle("启用", isOn: Binding(get: { m.state.hasEnabled(p.id) }, set: { on in
                        if on { m.activate(p) } else { m.send("setPackageEnabled", ["packageID": p.id, "enabled": false]) }
                    }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.caption)
                    .fixedSize()
                    .accessibilityLabel(Text("启用 \(item.title(code))"))
                    .accessibilityIdentifier("market.enable." + p.id)
                    .disabled(m.state.building(p.id) || p.actions["setEnabled"] as? Bool == false)
                }
                if target == .codex && BuiltInPackages.ids.contains(item.id) { Label("内置",systemImage:"lock").font(.caption).foregroundStyle(.secondary) }
                MarketStatus(health:health(item),compact:false)
                if let package = item.installed, !BuiltInPackages.ids.contains(package.id) {
                    Button { removalCandidate = package } label: {
                        Label("移除插件", systemImage: "minus.circle")
                    }
                    .disabled(!m.canRemovePlugin(package))
                    .accessibilityIdentifier("market.removePlugin")
                }
            }
            if !item.summary(code).isEmpty { Text(verbatim:item.summary(code)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
            PackageExample(id:item.id, title:item.title(code)).id(item.id)
            Divider()
            Text("安装详情").font(.headline)
            LabeledContent("插件标识") { Text(verbatim:item.id).textSelection(.enabled) }
            if let p = item.installed {
                LabeledContent("已安装版本") { Text(verbatim:p.version) }
                if let reason = p.node["reason"] as? String, !reason.isEmpty { NodePermissionDetails(packageID: p.id, reason: reason) }
                installedControls(p,status:health(item))
            } else if item.catalog?.builtInCeladon == true { WeChatLauncher() }
            else if let entry = item.catalog, let market {
                LabeledContent("可安装版本") { Text(verbatim:entry.version) }
                Button("安装…"){ m.prepareMarketInstall(entry,from:market) }.buttonStyle(.borderedProminent)
                    .disabled(!m.state.ready || m.transferBusy || m.preview != nil || target != .codex)
            }
            if let url = item.catalog?.source { Link(destination:url) { Label("插件源码",systemImage:"arrow.up.right") }.font(.caption) }
        }.padding(17).frame(maxWidth:.infinity,alignment:.leading).packpierCard()
    }

    private func installedControls(_ p:TweakPackage,status:MarketHealth) -> some View {
        VStack(alignment:.leading,spacing:9) {
            if let issue = m.state.failure(p.id) ?? p.fields["validationError"] as? String ?? p.node["lastError"] as? String, !issue.isEmpty {
                Text(verbatim:PPText.get(issue)).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if status == .waiting {
                Text(PPText.get(m.state.label(p))).font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in:.horizontal) {
                HStack { buttons(p,status:status) }
                VStack(alignment:.leading) { buttons(p,status:status) }
            }
        }
    }
    @ViewBuilder private func buttons(_ p:TweakPackage,status:MarketHealth) -> some View {
        if p.canAuthorize && m.state.hasEnabled(p.id) {
            Button("允许当前版本…"){ m.requestTrust(p) }.buttonStyle(.borderedProminent)
        } else {
            Button(PPText.get(p.hasBuild ? "重新编译" : "编译")){ m.send("buildPackage",["packageID":p.id]) }.disabled(!p.canBuild || m.state.building(p.id))
        }
        Button { m.chooseExport(p) } label: {
            Label(LocalizedStringKey(m.exportingID == p.id ? "正在导出…" : "导出 ZIP"),systemImage:"square.and.arrow.up")
        }.disabled(!m.canExport(p))
        Button { NSWorkspace.shared.open(URL(fileURLWithPath:p.directory,isDirectory:true)) } label: { Image(systemName:"folder") }
            .help("打开插件包目录").accessibilityLabel(Text("打开插件包目录")).disabled(p.directory.isEmpty)
        if status == .fault { Button("打开日志文件位置",action:m.revealLog) }
    }
    private func packageGrip(_ p:TweakPackage) -> some View {
            let ids = m.state.packages.map(\.id)
            let index = ids.firstIndex(of:p.id)
            return PackageGrip(id:p.id,title:p.title,drag:drag,enabled:m.state.ready && !m.ordering && ids.count > 1,
                move:{ target,after in Task { await m.movePackage(p.id,to:target,after:after) } },
                step:{ down in
                    guard let index else { return }
                    let target = index + (down ? 1 : -1)
                    if ids.indices.contains(target) { Task { await m.movePackage(p.id,to:ids[target],after:down) } }
                },canMoveUp:(index ?? 0)>0,canMoveDown:(index ?? ids.count)+1<ids.count)
                .frame(width:24,height:25)
    }
}
