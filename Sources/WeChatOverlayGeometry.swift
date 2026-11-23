import AppKit
import ApplicationServices

// All inputs use the top-left screen coordinates reported by Accessibility.
struct WeChatOverlayGeometry: Equatable {
    let button: CGRect
    let tint: CGRect

    init?(window: CGRect, search: CGRect, list: CGRect) {
        guard window.contains(search), search.width >= 64, (14...58).contains(search.height),
              search.minX - window.minX < min(160,window.width * 0.4), search.minY - window.minY < 105,
              list.minX <= search.minX + 10, list.maxX >= search.maxX - 4,
              list.minY >= search.maxY - 3, list.minY <= search.maxY + 66,
              list.height >= 70, list.minX >= window.minX - 2, list.maxX <= window.maxX + 2,
              list.minX - window.minX < min(140,window.width * 0.35),
              list.intersection(window).height > 64 else { return nil }
        let size = min(search.height - 2, 22)
        button = CGRect(x:search.maxX - size - 2,y:search.midY - size / 2,width:size,height:size)
        tint = list.intersection(window)
    }

    static func appKitRect(_ rect:CGRect, desktopTop:CGFloat) -> CGRect {
        CGRect(x:rect.minX,y:desktopTop - rect.maxY,width:rect.width,height:rect.height)
    }
}

struct WeChatWindowLayout {
    let frame: CGRect
    let geometry: WeChatOverlayGeometry

    // Never query AXValue or any row contents. Stop traversal at text/list controls.
    static func read(pid:pid_t) -> Self? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        func attribute(_ el:AXUIElement,_ name:String) -> CFTypeRef? {
            var value:CFTypeRef?
            return AXUIElementCopyAttributeValue(el,name as CFString,&value) == .success ? value : nil
        }
        func rect(_ el:AXUIElement) -> CGRect? {
            guard let p = attribute(el,kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
                  let s = attribute(el,kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
            var origin = CGPoint.zero, size = CGSize.zero
            guard AXValueGetValue(p as! AXValue,.cgPoint,&origin), AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil }
            return CGRect(origin:origin,size:size)
        }
        guard let raw = attribute(app,kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let window = raw as! AXUIElement
        guard let frame = rect(window), frame.width >= 280 else { return nil }
        var queue = [window], fields = [CGRect](), lists = [CGRect]()
        var index = 0
        while index < queue.count && index < 140 {
            let el = queue[index]
            index += 1
            let role = attribute(el,kAXRoleAttribute) as? String ?? ""
            switch role {
            case kAXTextFieldRole, "AXSearchField", kAXComboBoxRole:
                let subrole = attribute(el,kAXSubroleAttribute) as? String
                let placeholder = attribute(el,kAXPlaceholderValueAttribute) as? String ?? ""
                if role == "AXSearchField" || subrole == "AXSearchField" ||
                    ["搜索","搜尋","Search"].contains(where:{placeholder.localizedCaseInsensitiveContains($0)}) {
                    if let r = rect(el) { fields.append(r) }
                }
            case kAXScrollAreaRole,kAXTableRole,kAXListRole,kAXOutlineRole:
                if let r = rect(el) { lists.append(r) }
            case kAXWindowRole,kAXGroupRole,kAXSplitGroupRole,kAXToolbarRole,"AXLayoutArea","AXUnknown":
                var children: CFArray?
                if AXUIElementCopyAttributeValues(el,kAXChildrenAttribute as CFString,0,32,&children) == .success,
                   let items = children as? [AXUIElement] { queue.append(contentsOf:items) }
            default: break
            }
        }
        for field in fields {
            for list in lists.sorted(by:{ $0.height > $1.height }) {
                if let geometry = WeChatOverlayGeometry(window:frame,search:field,list:list) {
                    return Self(frame:frame,geometry:geometry)
                }
            }
        }
        return nil
    }
}
