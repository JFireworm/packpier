import SwiftUI
import AppKit
import ServiceManagement

@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    let manager = Manager()
    var openMainWindow: (() -> Void)?
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let domain = Bundle.main.bundleIdentifier,
              Bundle.main.object(forInfoDictionaryKey:"PackpierWeChatTestMode") as? Bool != true else { return }
        let service = SMAppService.mainApp
        do {
            try LoginItemDefaults.apply(defaults: .standard, domain: domain, status: service.status) {
                try service.register()
            }
        } catch {
            NSLog("Packpier login item registration failed: %@", error.localizedDescription)
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppUpdates.shared
        if Bundle.main.object(forInfoDictionaryKey:"PackpierWeChatTestMode") as? Bool == true {
            WeChatOverlay.shared.restore()
            manager.showInstalled(for:.wechat)
            return
        }
        manager.begin()
        let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
        if args.count == 2, args[0] == "--add-local", args[1].hasPrefix("/") {
            manager.addFromCommandLine(URL(fileURLWithPath:args[1]))
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let file = urls.first(where: \.isFileURL) { manager.readFile(file) }
    }
    private func presentMainWindow() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps:true)
        if let window = NSApp.windows.first(where:{ $0.identifier?.rawValue == "manager" || $0.title == "Packpier" }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { presentMainWindow() }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        manager.finish { DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate:true) } }
        return .terminateLater
    }
}

#if !PACKPIER_TEST
@main
#endif
struct PackpierApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    @AppStorage(PPText.languageKey) var language = "system"
    var body: some Scene {
        Window("Packpier", id:"manager") {
            ManagerWindow(delegate:delegate)
        }
            .windowToolbarStyle(.unified(showsTitle:false))
            .defaultSize(width:1050,height:685)
            .commands { PackageCommands(m:delegate.manager,language:language) }
    }
}

private struct ManagerWindow: View {
    let delegate: Delegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Dashboard(m:delegate.manager)
            .onAppear { [openWindow] in delegate.openMainWindow = { openWindow(id:"manager") } }
    }
}

private struct PackageCommands: Commands {
    @ObservedObject var m: Manager
    let language: String
    var body: some Commands {
        CommandGroup(replacing:.newItem) {
            Button(PPText.get("安装插件包…",language:language)) { m.chooseFile() }
                .keyboardShortcut("o").disabled(m.target != .codex)
        }
    }
}

struct Dashboard: View {
    @ObservedObject var m: Manager
    @StateObject var drag = PackageDrag()
    @State private var connectionInfo = false
    @AppStorage("packpier.sidebarCollapsed") private var collapsed = false
    @Environment(\.colorScheme) private var scheme
    @AppStorage(PPText.languageKey) var language = "system"
    @AppStorage("packpier.appearance") var appearance = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pages = [("插件市场","shippingbox"),("设置与更新","gearshape"),("关于","info.circle")]
    private var sidebarWidth: CGFloat { PPText.resolved(language) == "en" ? 202 : 180 }
    var body: some View {
        HStack(spacing:0) {
            sidebar
                .frame(width:collapsed ? 0 : sidebarWidth,alignment:.trailing)
                .clipped()
                .opacity(collapsed ? 0 : 1)
                .allowsHitTesting(!collapsed).accessibilityHidden(collapsed)
                .padding(.trailing,collapsed ? 0 : 8)
            VStack(alignment:.leading,spacing:0) {
                Color(nsColor:.windowBackgroundColor)
                    .frame(height:44).fixedSize(horizontal:false,vertical:true)
                    .overlay(alignment:.bottom) { Divider() }
                    .accessibilityHidden(true).allowsHitTesting(false).zIndex(1)
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        if m.page == "插件市场" {
                            marketplace
                        } else if m.page == "设置与更新" {
                            SettingsPage(appearance:$appearance,language:$language,revealLog:m.revealLog)
                        } else {
                            AboutPage()
                        }
                    }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                }.clipped()
            }.background(Color(nsColor:.windowBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:17))
            .overlay { RoundedRectangle(cornerRadius:17).strokeBorder(.primary.opacity(0.08)).allowsHitTesting(false) }
        }.padding(8).background(.regularMaterial).ignoresSafeArea(.container,edges:.top).frame(minWidth:850,minHeight:515)
        .toolbar {
            ToolbarItem(placement:.navigation) {
                HStack(spacing:0) {
                    collapseButton
                        .padding(.leading,collapsed ? 0 : sidebarWidth - 118)
                    Text(LocalizedStringKey(m.page)).font(.system(size:17,weight:.semibold))
                        .padding(.leading,collapsed ? 14 : 32)
                        .accessibilityAddTraits(.isHeader)
                }.fixedSize()
            }
        }
        .toolbarBackground(.hidden,for:.windowToolbar)
        .onDisappear { drag.cancel() }
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .popover(isPresented:$connectionInfo) {
            VStack(alignment:.leading,spacing:10) {
                Text("连接详情").font(.headline)
                LabeledContent("插件加载器") {
                    Text(LocalizedStringKey(m.state.ready ? "已响应" : "尚未收到响应"))
                }
                LabeledContent("Codex 窗口") {
                    Text(LocalizedStringKey(m.connection))
                }
                if let version = Bundle.main.object(forInfoDictionaryKey:"PackpierNodeVersion") as? String {
                    LabeledContent("内置运行环境",value:"Node.js " + version)
                }
                if let detail = (m.state.raw["status"] as? Fields)?["message"] as? String, !detail.isEmpty {
                    Text(verbatim:detail).font(.callout).textSelection(.enabled)
                }
            }.padding(20)
        }
        .sheet(item:$m.preview) { item in importSheet(item) }
        .sheet(item:$m.authorization) { ticket in permissionSheet(ticket) }
        .alert("Packpier",isPresented:Binding(get:{ m.error != nil },set:{ if !$0 { m.error = nil } })) {
            Button("好"){ m.error = nil }
        } message: { Text(PPText.get(m.error ?? "")) }
        .environment(\.locale,Locale(identifier:PPText.resolved(language)))
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:4) {
            Color.clear.frame(height:34).accessibilityHidden(true)
            ForEach(pages,id:\.0) { item in
                Button {
                    guard m.page != item.0 else { return }
                    m.page = item.0
                } label: {
                    HStack(spacing:10) {
                        Image(systemName:item.1).frame(width:18).accessibilityHidden(true)
                        Text(LocalizedStringKey(item.0)).lineLimit(1).fixedSize(horizontal:true,vertical:false)
                    }
                        .font(.system(size:14,weight:.medium))
                        .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).frame(height:35)
                        .foregroundStyle(m.page == item.0 ? Color.white : Color.primary)
                        .background(m.page == item.0 ? Color.accentColor : Color.clear,in:RoundedRectangle(cornerRadius:7))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(m.page == item.0 ? .isSelected : [])
            }
            Spacer()
        }
        .padding(10).frame(width:sidebarWidth)
        .background(LinearGradient(colors:scheme == .dark ? [Color(red:0.12,green:0.17,blue:0.21),Color(nsColor:.controlBackgroundColor)] : [Color(red:0.89,green:0.97,blue:0.99),Color(red:0.95,green:0.97,blue:0.98)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:17))
    }

    private var collapseButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration:0.24)) { collapsed.toggle() }
        } label: {
            Image(systemName:"sidebar.left").font(.system(size:16)).frame(width:30,height:26).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("navigation.collapse")
         .accessibilityLabel(Text(LocalizedStringKey(collapsed ? "展开侧栏" : "收起侧栏")))
         .help(LocalizedStringKey(collapsed ? "展开侧栏" : "收起侧栏"))
    }

    @ViewBuilder var marketplace: some View {
        let targets = HStack(spacing:10) {
            LabeledContent("目标应用") { Text(verbatim:PPText.get(m.target.displayName)) }
                .fixedSize().accessibilityIdentifier("market.selection")
            Button("添加应用（开发中）", systemImage:"plus") {}
                .disabled(true).accessibilityIdentifier("market.add")
        }.fixedSize()
        let actions = HStack(spacing:8) {
            if m.target == .codex {
                Button("安装插件包",systemImage:"arrow.down.to.line") { m.chooseFile() }
                    .buttonStyle(.borderedProminent).tint(.blue)
                    .accessibilityIdentifier("market.installPackage")
                    .disabled(m.transferBusy || m.choosing || !m.state.ready)
            }
            CopyDeveloperSkillButton {
                do { try AuthorSkill.copy(); m.notice = "已复制 Skill 正文" }
                catch { m.error = "未能复制 Skill" }
            }
            if m.target == .codex {
                Menu {
                    Toggle("启用加载器",isOn:Binding(get:{ m.state.enabled },set:{ m.send("setEnabled",["enabled":$0]) })).disabled(!m.state.ready)
                    Button("重新扫描") { m.send("reloadPackages") }.disabled(!m.state.ready)
                    Button("连接详情") { connectionInfo = true }
                } label: { Label("应用工具",systemImage:"slider.horizontal.3") }
            }
        }.fixedSize()
        ViewThatFits(in:.horizontal) {
            HStack { targets; Spacer(minLength:10); actions }
            VStack(alignment:.leading,spacing:8) {
                targets
                HStack { Spacer(); actions }
            }
        }.zIndex(1)
        MarketplacePage(m:m,drag:drag,target:m.target,showConnection:{ connectionInfo = true })
    }
    func importSheet(_ file:LocalPackage) -> some View {
        let existing = m.state.packages.first(where: { $0.id == file.name })
        return VStack(alignment:.leading,spacing:15) {
            Label("安装插件包",systemImage:"shippingbox").font(.title2.bold())
            LabeledContent("文件",value:file.fileName)
            LabeledContent("目标应用",value:"Codex")
            LabeledContent("插件包",value:"\(file.name) · v\(file.version)")
            if let reason = file.reason, !reason.isEmpty { NodePermissionDetails(packageID: file.name, reason: reason) }
            if let existing { Text("本机已有 \(existing.id) \(existing.version)。继续将使用已安装的副本。").foregroundStyle(.secondary) }
            HStack { Spacer(); Button("取消"){ m.preview = nil }.keyboardShortcut(.cancelAction)
                Button(PPText.get(existing == nil ? "添加到 Codex 并启用" : "使用已安装的版本")){ m.confirmImport() }
                    .keyboardShortcut(.defaultAction).disabled(!m.state.ready || (existing != nil && existing?.version != file.version))
            }
        }.padding(25).frame(width:450)
    }
    func permissionSheet(_ ticket:Manager.Authorization) -> some View {
        VStack(alignment:.leading,spacing:14) {
            Label("允许当前版本运行 Node？",systemImage:"lock.shield").font(.title2.bold())
            Text("\(ticket.packageID) · v\(ticket.version)").font(.headline)
            if !ticket.reason.isEmpty { NodePermissionDetails(packageID: ticket.packageID, reason: ticket.reason) }
            Text("允许后，这个构建可以用你的本机用户权限运行 Node 代码。").foregroundStyle(.secondary)
            HStack { Spacer(); Button("取消"){ m.authorization = nil }.keyboardShortcut(.cancelAction)
                Button("允许当前版本"){ m.confirmTrust(ticket) }.buttonStyle(.borderedProminent) }
        }.padding(25).frame(width:440)
    }
}

struct BrandIcon: View {
    let size: CGFloat
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable().interpolation(.high).scaledToFit()
            .frame(width:size, height:size).accessibilityHidden(true)
    }
}

struct LogTextView: NSViewRepresentable {
    let text: String
    let zone: TimeZone
    final class Cache {
        var text: String?
        var zone: TimeZone?
    }
    func makeCoordinator() -> Cache { Cache() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.isEditable = false
        view.isRichText = false
        view.isSelectable = true
        view.usesFindBar = true
        view.drawsBackground = false
        scroll.drawsBackground = false
        view.font = .monospacedSystemFont(ofSize:NSFont.systemFontSize, weight:.regular)
        view.textColor = .labelColor
        view.textContainerInset = NSSize(width:14,height:14)
        view.textContainer?.lineFragmentPadding = 0
        view.layoutManager?.allowsNonContiguousLayout = true
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let cache = context.coordinator
        guard let view = scroll.documentView as? NSTextView, cache.text != text || cache.zone != zone else { return }
        cache.text = text
        cache.zone = zone
        view.string = LogTimestamps.display(text,in:zone)
    }
}
