import AppKit
import ServiceManagement
import SwiftUI

private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius:12,style:.continuous)
        content
            .background(.primary.opacity(scheme == .dark ? 0.065 : 0.045),in:shape)
            .overlay { shape.strokeBorder(.primary.opacity(0.10)).allowsHitTesting(false) }
    }
}

extension View {
    func packpierCard() -> some View { modifier(CardSurface()) }
}

private struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(LocalizedStringKey(title)).font(.headline)
            content()
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).packpierCard()
    }
}

struct SettingsPage: View {
    @Binding var appearance: String
    @Binding var language: String
    let revealLog: () -> Void
    var body: some View {
        Panel(title:"Packpier 版本") {
            HStack(spacing:12) {
                BrandIcon(size:48)
                VStack(alignment:.leading,spacing:4) {
                    Text("Packpier").font(.title2.weight(.semibold))
                    let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—"
                    let build = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—"
                    Text("本地版本 \(version)（\(build)）").foregroundStyle(.secondary)
                }
                Spacer()
                CheckForUpdatesButton()
            }
            Divider()
            UpdateSettings()
        }
        LoginItemRow()
        Panel(title:"外观与语言") {
            Picker("外观",selection:$appearance) {
                Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
            }.fixedSize()
            Divider()
            Picker("显示语言",selection:$language) {
                Text("跟随系统").tag("system")
                ForEach(PPText.languages,id:\.code) { option in
                    Text(verbatim:option.name).tag(option.code)
                }
            }.fixedSize()
        }
        Panel(title:"运行日志") {
            Button("打开日志文件位置",systemImage:"folder",action:revealLog)
                .accessibilityIdentifier("settings.revealLog")
        }
    }
}

private struct LoginItemRow: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:14) {
                Image(systemName:"power").font(.title2).foregroundStyle(.tint).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4) {
                    Text("开机自动启动").font(.headline)
                    Text("登录 Mac 时自动打开 Packpier。").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("开机自动启动",isOn:Binding(get:{ status == .enabled || status == .requiresApproval },set:setEnabled))
                    .labelsHidden().toggleStyle(.switch).accessibilityIdentifier("settings.launchAtLogin")
            }
            if status == .requiresApproval {
                HStack {
                    Text("等待 macOS 允许登录启动。").foregroundStyle(.secondary)
                    Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            if let failure { Text(verbatim:failure).font(.callout).foregroundStyle(.secondary) }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).packpierCard()
        .onAppear { status = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }

    private func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        failure = nil
        do {
            if enabled { try service.register() } else { try service.unregister() }
            LoginItemDefaults.finish(.standard)
        } catch {
            failure = PPText.format("登录项设置失败（%@）",error.localizedDescription)
        }
        status = service.status
    }
}

struct AboutPage: View {
    var body: some View {
        HStack(spacing:15) {
            BrandIcon(size:60)
            VStack(alignment:.leading,spacing:6) {
                Text("Packpier").font(.title.bold())
                Text("为已添加的应用发现、安装和管理插件。").foregroundStyle(.secondary)
            }
        }.padding(.vertical,8)
        Panel(title:"项目主页") {
            Link(destination:AppUpdates.homepage) { Label("Packpier 项目主页",systemImage:"arrow.up.right.square") }
        }
    }
}
