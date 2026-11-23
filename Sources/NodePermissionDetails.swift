import SwiftUI

struct NodePermissionDetails: View {
    let packageID: String
    let reason: String

    private struct Use {
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    // Only format declarations we recognize. A local package or a future release may request different uses.
    private var uses: [Use] {
        switch (packageID, reason) {
        case ("prism", "读取本机 Codex 项目和会话归属、加载器语言设置和系统语言偏好，将配色保存在 Prism 数据目录。"),
             ("prism", "读取本机 Codex 项目和会话归属、Tweaks 语言设置和系统语言偏好，将配色保存在 Prism 数据目录。"):
            return [
                Use(title: "会话与项目", detail: "读取本机 Codex 的项目列表、会话归属和置顶顺序。"),
                Use(title: "显示语言", detail: "读取加载器的语言设置，跟随系统时读取 macOS 语言偏好。"),
                Use(title: "配色设置", detail: "将项目和会话的配色保存在本机 Prism 数据目录。")
            ]
        case ("custom-background", "用于获取背景图片、将收藏存入「图片/Packpier/收藏」、将导出图片写入「下载」，并调用 macOS 图像工具把图片复制到系统剪贴板。"):
            return [
                Use(title: "获取图片", detail: "从网络获取背景图片。"),
                Use(title: "保存图片", detail: "收藏的图片保存在「图片/Packpier/收藏」，手动保存的图片写入「下载」文件夹。"),
                Use(title: "复制图片", detail: "调用 macOS 图像工具，将所选图片复制到系统剪贴板。")
            ]
        default:
            return []
        }
    }

    var body: some View {
        let rows = uses
        VStack(alignment: .leading, spacing: 8) {
            Label("Node.js 权限用途", systemImage: "lock.shield").font(.subheadline.weight(.semibold))
            if rows.isEmpty {
                Text(verbatim: reason)
            } else {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(rows.indices, id: \.self) { index in
                        GridRow {
                            Text(rows[index].title).foregroundStyle(.secondary).fixedSize()
                            Text(rows[index].detail).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .font(.callout)
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}
