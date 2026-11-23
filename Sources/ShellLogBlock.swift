import AppKit
import SwiftUI

struct ShellLogBlock: View {
    let text: String
    let zone: TimeZone
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false

    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Spacer()
                Button {
                    copied = Self.copy(text,in:zone,to:.general)
                } label: {
                    Image(systemName:copied ? "checkmark" : "doc.on.doc")
                        .frame(width:22,height:22)
                }.buttonStyle(.borderless)
                    .accessibilityLabel(copied ? Text("已复制") : Text("复制日志预览"))
                    .help(copied ? PPText.get("已复制") : PPText.get("复制日志预览"))
                    .disabled(text.isEmpty)
            }.padding(.horizontal,14).padding(.top,9)
            if text.isEmpty {
                Text("暂无加载器日志").foregroundStyle(.secondary).padding(14)
                Spacer()
            } else {
                LogTextView(text:text,zone:zone)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(scheme == .dark ? Color(red:0.145,green:0.155,blue:0.175)
                                        : Color(red:0.902,green:0.910,blue:0.922))
            .clipShape(RoundedRectangle(cornerRadius:8,style:.continuous))
            .task(id:copied) {
                guard copied else { return }
                do { try await Task.sleep(nanoseconds:1_500_000_000); copied = false } catch {}
            }
    }

    @MainActor static func copy(_ text:String,in zone:TimeZone,to board:NSPasteboard) -> Bool {
        guard !text.isEmpty else { return false }
        let rendered = LogTimestamps.display(text,in:zone)
        board.clearContents()
        return board.setString(rendered,forType:.string)
    }
}
