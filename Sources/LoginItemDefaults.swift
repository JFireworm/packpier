import Foundation
import ServiceManagement

enum LoginItemDefaults {
    static func apply(defaults: UserDefaults, domain: String, status: SMAppService.Status,
                      register: () throws -> Void) throws {
        let key = "packpier.loginItemDefaultApplied"
        guard !defaults.bool(forKey: key) else { return }

        // Older builds stored the login setting only in macOS. Preserve that choice on upgrade.
        let saved = defaults.persistentDomain(forName: domain) ?? [:]
        let existingInstall = saved["NSWindow Frame manager"] != nil || saved.keys.contains { $0.hasPrefix("packpier.") }
        defaults.set(true, forKey: key)
        if !existingInstall && status == .notRegistered {
            try register()
        }
    }
}
