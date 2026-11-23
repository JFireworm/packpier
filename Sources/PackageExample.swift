import SwiftUI

struct MarketIcon: View {
    let id: String
    let symbol: String
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme
    private static let brush = Bundle.main.url(forResource:"p-sign-mark",withExtension:"png",subdirectory:"Marketplace/Previews").flatMap(NSImage.init(contentsOf:))
    private static let prismMark = Bundle.main.url(forResource: "prism-mark", withExtension: "svg", subdirectory: "Marketplace/Previews")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if id == "prism", let mark = Self.prismMark {
            Image(nsImage: mark).renderingMode(.original).resizable().scaledToFit()
                .frame(width: size, height: size).accessibilityHidden(true)
        } else if id == "p-sign", let brush = Self.brush {
            Image(nsImage:brush).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(scheme == .dark ? Color(red:0.66,green:0.77,blue:1) : Color(red:0.16,green:0.30,blue:0.71))
                .frame(width:size,height:size).shadow(color:.cyan.opacity(0.5),radius:0,x:0.5,y:0.4).accessibilityHidden(true)
        } else {
            Image(systemName:symbol).font(.system(size:size)).foregroundStyle(.tint).frame(width:size,height:size).accessibilityHidden(true)
        }
    }
}

struct PackageExample: View {
    let id: String
    let title: String
    @State private var enlarged = false
    @Environment(\.colorScheme) private var colorScheme

    private static let images: [String: NSImage] = Dictionary(uniqueKeysWithValues:
        BuiltInPackages.ids.flatMap { [$0, $0 + "-dark"] }.compactMap { id in
            guard let url = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "Marketplace/Previews"),
                  let image = NSImage(contentsOf: url) else { return nil }
            return (id, image)
        }
    )

    private var themeName: LocalizedStringKey { colorScheme == .dark ? "深色" : "浅色" }

    var body: some View {
        if let image = Self.images[colorScheme == .dark ? id + "-dark" : id] {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("使用效果").font(.headline)
                    Spacer()
                    Button { enlarged = true } label: {
                        Label("放大演示图", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
                Button { enlarged = true } label: {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("放大演示图"))
            }
            .sheet(isPresented: $enlarged) {
                let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1024, height: 768)
                let scale = min(1, (screen.width - 80) / image.size.width, (screen.height - 150) / image.size.height)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(verbatim: title).font(.headline)
                        Spacer()
                        Button("关闭预览") { enlarged = false }.keyboardShortcut(.cancelAction)
                    }
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: image.size.width * scale, height: image.size.height * scale)
                        .accessibilityLabel(Text(verbatim: title))
                        .accessibilityValue(Text(themeName))
                }.padding(16)
            }
            .accessibilityIdentifier("market.example." + id)
        } else if id == "wechat-celadon" {
            VStack(alignment: .leading, spacing: 8) {
                Text("使用效果").font(.headline)
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("WeChat", systemImage: "macwindow").font(.caption.bold())
                        Divider().overlay(.white.opacity(0.25))
                        Text("青瓷").padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.mint.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    }.foregroundStyle(.white).padding(14).frame(maxWidth: 440, alignment: .leading)
                        .background(Color(red: 0.10, green: 0.14, blue: 0.18).opacity(0.87), in: RoundedRectangle(cornerRadius: 9)).padding(18)
                }.frame(maxWidth: .infinity, minHeight: 175).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("查看当前微信版本的适配状态，管理青瓷主题。").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
