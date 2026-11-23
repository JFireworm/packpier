import AppKit
import SwiftUI

struct MarketApp: Identifiable, Codable, Equatable {
    let bundleID: String
    let name: String
    let path: String?

    var id: String { bundleID.lowercased() }

    static func known(_ target: PackageTarget) -> Self {
        let identifier: String
        switch target {
        case .codex: identifier = "com.openai.codex"
        case .wechat: identifier = "com.tencent.xinWeChat"
        case .feishu: identifier = "com.electron.lark"
        }
        return Self(bundleID:identifier,name:target.displayName,path:nil)
    }
    static let catalog = PackageTarget.allCases.map(known)
    var target: PackageTarget? { PackageTarget.allCases.first { Self.known($0).id == id } }
    var title: String { target.map { PPText.get($0.displayName) } ?? name }
    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundleID) ??
            path.map(URL.init(fileURLWithPath:)).flatMap { Bundle(url:$0)?.bundleIdentifier?.lowercased() == id ? $0 : nil }
    }

    init(bundleID: String, name:String, path:String?) {
        self.bundleID=bundleID; self.name=name; self.path=path
    }
    init(url: URL) throws {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url:url),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty,
              bundle.object(forInfoDictionaryKey:"CFBundlePackageType") as? String == "APPL" else {
            throw PackpierError.message("请选择有效的 macOS 应用。")
        }
        if let app = Self.catalog.first(where:{ $0.id == identifier.lowercased() }) {
            self = app
        } else {
            self.init(bundleID:identifier,name:FileManager.default.displayName(atPath:url.deletingPathExtension().path),path:url.path)
        }
    }
}

struct MarketApplications: Codable, Equatable {
    static let key = "packpier.marketApplications.v1"
    private(set) var apps: [MarketApp]
    private(set) var selectedID: String?
    var selected: MarketApp? { apps.first { $0.id == selectedID } }

    static func load(from defaults:UserDefaults) -> Self {
        guard defaults.object(forKey:key) != nil else {
            let codex = MarketApp.known(.codex)
            return Self(apps:[codex],selectedID:codex.id)
        }
        guard let data = defaults.data(forKey:key),
              var saved = try? JSONDecoder().decode(Self.self,from:data) else { return Self(apps:[],selectedID:nil) }
        if saved.selected == nil { saved.selectedID = saved.apps.first?.id }
        return saved
    }

    func save(to defaults:UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data,forKey:Self.key) }
    }
    mutating func add(_ app:MarketApp) {
        if let index = apps.firstIndex(where:{ $0.id == app.id }) { apps[index] = app }
        else { apps.append(app) }
        selectedID = app.id
    }
    mutating func select(_ id:String) {
        if apps.contains(where:{ $0.id == id }) { selectedID = id }
    }
    mutating func remove(_ id:String) {
        apps.removeAll { $0.id == id }
        if selectedID == id { selectedID = apps.first?.id }
    }
}

struct AddMarketApplication: View {
    @ObservedObject var m: Manager
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var fileError: String?

    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("添加应用").font(.title2.bold())
                Spacer()
                Button("完成"){ dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("搜索应用",text:$search).textFieldStyle(.roundedBorder)
            let candidates = (MarketApp.catalog + m.marketApps.apps.filter { $0.target == nil }).filter {
                search.isEmpty || [$0.title,$0.name,$0.bundleID,$0.target?.rawValue ?? ""].contains { $0.localizedCaseInsensitiveContains(search) }
            }
            ScrollView {
                VStack(spacing:0) {
                    ForEach(candidates) { app in
                        let added = m.marketApps.apps.contains { $0.id == app.id }
                        HStack(spacing:12) {
                            if let url = app.applicationURL {
                                Image(nsImage:NSWorkspace.shared.icon(forFile:url.path)).resizable().frame(width:28,height:28)
                            } else { Image(systemName:"app").frame(width:28,height:28) }
                            Text(verbatim:app.title)
                            Spacer()
                            Button(added ? PPText.get("已添加") : PPText.get("添加")) {
                                m.addMarketApp(app)
                                dismiss()
                            }.accessibilityIdentifier("market.add." + app.id)
                        }.frame(minHeight:44)
                        Divider()
                    }
                    if candidates.isEmpty { Text("没有匹配的应用").foregroundStyle(.secondary).padding() }
                }
            }.frame(height:164)
            Button("从本机选择应用…",systemImage:"folder"){ chooseLocal() }
            if let fileError { Text(PPText.get(fileError)).foregroundStyle(.red).font(.callout) }
        }.padding(22).frame(width:400)
    }

    private func chooseLocal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath:"/Applications",isDirectory:true)
        let complete: (NSApplication.ModalResponse) -> Void = { result in
            guard result == .OK, let url = panel.url else { return }
            do { m.addMarketApp(try MarketApp(url:url)); dismiss() }
            catch { fileError = error.localizedDescription }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for:window,completionHandler:complete) }
        else { panel.begin(completionHandler:complete) }
    }
}

