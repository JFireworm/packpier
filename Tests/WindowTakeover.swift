import Foundation

@main enum WindowTakeover {
    static func main() async throws {
        let args = CommandLine.arguments
        guard let url = URL(string: args[1]), url.scheme == "ws", url.host == "127.0.0.1" else {
            throw WireError.message("Expected an isolated browser fixture")
        }
        let bundle = try String(contentsOfFile: args[2], encoding: .utf8)
        let page = CDPPage(targetID: "fixture", url: url)
        defer { page.close() }
        page.onBinding = { request in
            guard jsonString(request["plugin"]) == "prism", let id = jsonInt(request["id"]) else { return }
            Task {
                _ = try await page.evaluate("""
                    __packpierResolve(\(id),true,{account:"test",projects:[],threads:[],language:"en",
                    preferences:{mode:"all",colors:{"codex:thread:local:sample":"#FF79A9"},order:[]}})
                    """)
            }
        }
        try await page.open()
        _ = try await page.evaluate("""
            document.body.innerHTML = `<nav data-app-navigation-rail><div><div><div><button aria-haspopup="menu">Usage</button></div><div>Profile</div></div></div></nav>
                <aside data-sidebar-navigation-root><section data-app-action-sidebar-section data-app-action-sidebar-section-heading="Recents">
                <div data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="sample" data-app-action-sidebar-thread-kind="local">Sample chat</div>
                </section></aside><main></main>`;
            globalThis.oldClosed = 0;
            document.querySelector("main").innerHTML = '<div class="packpier-p-sign" data-old-effect></div>';
            globalThis.__PACKPIER__ = { version: "packpier-window-4", close() {
                document.querySelector("[data-old-effect]").remove();
                globalThis.oldClosed++;
            }};
            1
            """)
        let host = WindowInjection(page: page)
        var logs: [String] = []
        try await host.apply(bundle: bundle, version: "packpier-window-5", packages: ["p-sign", "prism"]) {
            logs.append($0)
        }
        precondition(logs.map { $0.split(separator: " ").first! } == ["probe", "closeOld", "addBinding", "bundle", "apply"])
        precondition(logs[0].contains("oldVersion=packpier-window-4"))
        precondition(host.connected && host.mounted == ["p-sign", "prism"])
        var rendered = false
        for _ in 0..<40 {
            let ready = try await page.evaluate("""
                __PACKPIER__.version === 'packpier-window-5' && oldClosed === 1
                && document.querySelectorAll('.packpier-p-sign').length === 1
                && document.querySelector('[data-app-action-sidebar-thread-row]').style.getPropertyValue('--prism-native-color') === '#FF79A9'
                """)
            if jsonBool(ready) == true { rendered = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(rendered, "Takeover did not restore Prism color")
        try await host.close()
        let cleaned = try await page.evaluate("""
            !globalThis.__PACKPIER__ && !document.querySelector('.packpier-p-sign,[data-prism-accent]')
            """)
        precondition(jsonBool(cleaned) == true)
        do {
            try await host.apply(bundle: "throw new Error('fixture bundle failure')", version: "packpier-window-5",
                                 packages: ["prism"]) { _ in }
            preconditionFailure("Expected bundle stage error")
        } catch {
            precondition(error.localizedDescription.hasPrefix("bundle:") &&
                         error.localizedDescription.contains("fixture bundle failure"))
        }
        precondition(!host.connected && host.mounted.isEmpty)
        print("PASS window-4 → window-5, one root, Prism color, teardown, staged error detail")
    }
}
