import Foundation
import ServiceManagement

enum LoginItemDefaults {
    private static let applied = "packpier.loginItemDefaultApplied"
    private static let pending = "packpier.loginItemRegistrationPending"

    static func finish(_ defaults: UserDefaults) {
        defaults.set(true, forKey: applied)
        defaults.removeObject(forKey: pending)
    }

    static func apply(defaults: UserDefaults, domain: String, status: SMAppService.Status,
                      canRegister: Bool = true,
                      register: () throws -> Void) throws {
        guard !defaults.bool(forKey: applied) else { return }

        if !defaults.bool(forKey: pending) {
            // Older releases kept the user's login choice in macOS.
            let saved = defaults.persistentDomain(forName: domain) ?? [:]
            if saved["NSWindow Frame manager"] != nil || saved["SUHasLaunchedBefore"] as? Bool == true {
                finish(defaults)
                return
            }
            defaults.set(true, forKey: pending)
        }

        guard canRegister else { return }
        switch status {
        case .notRegistered:
            try register()
        case .enabled, .requiresApproval:
            break
        default:
            return
        }
        finish(defaults)
    }
}
