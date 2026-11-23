import SwiftUI
import AppKit

enum AuthorSkill {
    static func text(in bundle:Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource:"SKILL",withExtension:"md",subdirectory:"Skills/packpier-plugin-author")
        else { throw CocoaError(.fileNoSuchFile) }
        return try String(contentsOf:url,encoding:.utf8)
    }
    @MainActor static func copy(from bundle:Bundle = .main,to board:NSPasteboard = .general) throws {
        let contents = try text(in:bundle)
        board.clearContents()
        guard board.setString(contents,forType:.string) else { throw CocoaError(.fileWriteUnknown) }
    }
}

struct AuthorSkillPanel: View {
    @State private var result = ""
    var body: some View {
        Divider()
        HStack {
            VStack(alignment:.leading,spacing:5) {
                Text("开发插件包").font(.headline)
                Text("把开发 Skill 交给 AI，按 Codex 适配器的协议编写和验证插件包。").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("复制 Skill",systemImage:"doc.on.doc") {
                do { try AuthorSkill.copy(); result = "已复制" } catch { result = "未能复制 Skill" }
            }
        }
        if !result.isEmpty { Text(LocalizedStringKey(result)).font(.callout) }
    }
}

struct CopyDeveloperSkillButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button("复制开发 Skill", systemImage: "doc.on.clipboard", action: action)
            .buttonStyle(.bordered)
            .foregroundStyle(hovered ? Color.accentColor : .primary)
            .accessibilityIdentifier("market.copySkill")
            .accessibilityHint("粘贴给 AI 生成插件包")
            .onHover { hovered = $0 }
            .overlay {
                GeometryReader { button in
                    if hovered {
                        Text("粘贴给 AI 生成插件包")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 190)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.3)) }
                            .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                            .accessibilityIdentifier("market.copySkillHint")
                            .frame(width: button.size.width)
                            .offset(y: button.size.height + 5)
                    }
                }.allowsHitTesting(false)
            }
            .onDisappear { hovered = false }
    }
}
