import Foundation

/// One page's connection and mounted state. Updates are serialized by WindowHost.
final class WindowInjection {
    let page: CDPPage
    let owner = UUID().uuidString
    private var bindingAdded = false
    private var applied: [String]?
    private(set) var mounted: [String] = []
    private(set) var errors: [String: String] = [:]
    var connected: Bool { applied != nil }

    init(page: CDPPage) { self.page = page }

    private var ownsRuntime: String {
        "globalThis.__PACKPIER__?.hostOwner === '\(owner)'"
    }

    func apply(bundle: String, version: String, packages: [String], log: (String) -> Void) async throws {
        var stage = ""
        var started = ProcessInfo.processInfo.systemUptime
        func elapsed() -> String {
            String(format: "%.0fms", (ProcessInfo.processInfo.systemUptime - started) * 1000)
        }
        func begin(_ next: String) throws {
            try Task.checkCancellation()
            stage = next
            started = ProcessInfo.processInfo.systemUptime
        }
        do {
            try begin("probe")
            let current = try await page.evaluate("""
                ({ version: globalThis.__PACKPIER__?.version ?? null,
                   owned: \(ownsRuntime), exists: Boolean(globalThis.__PACKPIER__) })
                """, timeout: 6) as? JSONObject
            let installedVersion = current?["version"] as? String
            let owned = current?["owned"] as? Bool == true && installedVersion == version
            if owned, applied == packages { return }
            log("probe ok \(elapsed()) oldVersion=\(installedVersion ?? "none")")
            if !owned, current?["exists"] as? Bool == true {
                try begin("closeOld")
                let oldError = try await page.evaluate("""
                    (() => {
                      try { globalThis.__PACKPIER__?.close?.(); return null; }
                      catch (error) { return String(error?.message ?? error); }
                      finally { delete globalThis.__PACKPIER__; }
                    })()
                    """, timeout: 8) as? String
                try await Task.sleep(for: .milliseconds(300))
                if let oldError { log("closeOld failed \(elapsed()) \(oldError); continuing with replacement") }
                else { log("closeOld ok \(elapsed())") }
            }
            if !bindingAdded {
                try begin("addBinding")
                _ = try await page.send("Runtime.addBinding", ["name": "__packpierRpc"], timeout: 6)
                bindingAdded = true
                log("addBinding ok \(elapsed())")
            }
            if !owned {
                try begin("bundle")
                let loaded = try await page.evaluate("""
                    (() => {
                      \(bundle)
                      const runtime = globalThis.__PACKPIER__;
                      if (runtime?.version !== '\(version)') throw new Error('Unexpected Packpier runtime version');
                      runtime.hostOwner = '\(owner)';
                      return 1;
                    })()
                    """, timeout: 30)
                guard jsonInt(loaded) == 1 else { throw WireError.message("Packpier runtime did not load") }
                log("bundle ok \(elapsed())")
            }
            try begin("apply")
            let state: JSONObject = ["enabled": true, "packages": packages.map { ["id": $0] }, "disabledPackageIDs": []]
            let result = try await page.evaluate("""
                \(ownsRuntime) ? globalThis.__PACKPIER__.apply(\(jsonLiteral(state))) : null
                """) as? JSONObject
            guard let result, let mounted = jsonStringList(result["mounted"]) else {
                throw WireError.message("Packpier runtime returned no mount result")
            }
            let errors = result["errors"] as? [String: String] ?? [:]
            if let error = errors["runtime"] { throw WireError.message(error) }
            self.mounted = mounted
            self.errors = errors
            applied = packages
            log("apply ok \(elapsed())")
        } catch {
            applied = nil
            mounted = []
            errors = [:]
            if error is CancellationError { throw error }
            let message = "\(stage): \(error.localizedDescription)"
            log("inject failed \(elapsed()) \(message)")
            throw WireError.message(message)
        }
    }

    func close() async throws {
        _ = try await page.evaluate("""
            if (\(ownsRuntime)) { globalThis.__PACKPIER__.close(); delete globalThis.__PACKPIER__; }
            1
            """, timeout: 3)
    }
}
