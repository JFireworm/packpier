# Packpier on Windows

The prototype is a native Windows x64 window that lists the three Codex plugins, their versions and localized descriptions. The project embeds [the shared catalog](../Resources/Marketplace/catalog.json). The window reads it through [Marketplace.cs](../Windows/Marketplace.cs) and gets its connection state from [ILoader](../Windows/Loader.cs). The preview loader reports `Unavailable`, so users can try the window with a clean profile and no Codex installation.

## Run the prototype

On a Windows x64 development machine with the .NET 10 SDK installed, run this command from the repository root.

```powershell
dotnet run --project Windows/Packpier.Windows.csproj -c Release
```

Select each plugin with the mouse or arrow keys. The detail pane shows the corresponding version and description. The list follows catalog order, and the descriptions fall back to English for unsupported locales.

On macOS with the .NET 10 SDK, `dotnet build Windows/Packpier.Windows.csproj -c Release` cross-compiles the Windows x64 host and WPF resources. To try an existing build on Windows x64, install the .NET 10 Desktop Runtime, copy the entire build output directory and run `Packpier.Windows.exe` alongside its DLL and JSON files. The 0.1.30 release provides a self-contained ZIP and includes the .NET 10 Desktop Runtime. Follow the [preview run instructions](../Windows/README.md). The extracted preview opened and closed normally on the GitHub Actions Windows x64 runner. Manual interaction and DPI scaling await desktop testing. [Microsoft cross-targeting guidance](https://learn.microsoft.com/en-us/dotnet/core/tools/sdk-errors/netsdk1100)

## Framework decision

| Option | What Packpier could share | Cost for this project |
| --- | --- | --- |
| **.NET / WPF** | Catalog, package fixtures, JSON contracts and the plugin renderer sources | Rebuild SwiftUI views in XAML and platform services in C#. Native desktop controls fit the current marketplace. The development build uses the Windows Desktop Runtime. [WPF overview](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/) |
| Tauri | Same assets and contracts, plus a future HTML marketplace shared across platforms | Build a web UI, Rust backend and WebView2 bridge. The existing macOS marketplace uses SwiftUI, so there is no HTML marketplace to share today. [Tauri architecture](https://v2.tauri.app/concept/architecture/) |
| Electron | Same assets and contracts, JavaScript tooling and a future HTML marketplace | Distribute Chromium and Node with the manager. Keep privileged operations in the main process and maintain a renderer/preload boundary. [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model) |

**Choice for the prototype:** WPF keeps the Windows window native and leaves the existing macOS product independently buildable. Windows host compatibility is the largest uncertainty across all three options.

## Reuse and platform work

| Area | Reuse | Windows implementation and acceptance |
| --- | --- | --- |
| Marketplace and package library | The catalog, `package.json` manifest, package IDs, version rules and the data models from `app-state.json` and `package-settings.json` | Port per-user storage, archive validation, atomic replacement and locking from [PluginLibrary.swift](../Loader/PluginLibrary.swift) to Windows. Use fixtures for order, enablement, malformed archives and upgrades. |
| Loader and CDP | The renderer lifecycle, message shapes and existing JavaScript and DOM fixtures | Port the Windows connection layer only if the host offers a compatible, authorized interface. Establish process identity, target ownership, reconnect and cleanup on a disposable profile. Keep the prototype's `Unavailable` state when host support is absent. |
| Built-in effects | P-Sign, Prism and Custom Background JS/CSS, JSON preferences and ID conventions | Check selector and RPC compatibility on Windows. Port [Prism's catalog access](../Loader/Services/PrismCatalog.swift) once the Windows data path and SQLite schema are verified. Port [background services](../Loader/Services/BackgroundService.swift) for image decoding, file storage and clipboard operations. |
| Third-party plugins | Manifest schema, approval data model and the [Node runner protocol](../Resources/NodeRunner/runner.mjs) | Port system Node discovery, executable validation, approval tracking and child cleanup. Keep the built-in effects independent of Node. |
| Distribution | Version scheme and release notes | Replace Sparkle, macOS login items and DMG packaging with a Windows update/install strategy. Verify signing, install, upgrade and uninstall on a clean Windows VM. |

## Delivery estimate

Assume one engineer, Windows 11 x64 test access and the three existing built-ins. Estimates are engineering days. Start with the host feasibility check before committing to the rest.

| Phase | Effort | Exit condition |
| --- | ---: | --- |
| Read-only shell, included here | 0.5–1 | Cross-build succeeds. On Windows, open the window, select all three entries via mouse and keyboard, check English and Simplified Chinese and repeat at 100% and 150% display scaling. |
| Host feasibility | 1–3 | Demonstrate a supported local connection and reversible test effect on an isolated Windows host. If the host lacks the capability, keep the market read-only and revisit which effects are possible. |
| Package library and loader | 3–5 | Import, reorder, toggle and remove fixture packages. Recover after relaunch and disconnect. |
| Three built-ins and native services | 4–7 | Verify colors, image selection and favorites, then verify cleanup after disable, refresh and exit. |
| Optional Node and distribution | 3–5 | Exercise approved/disabled/missing Node, then validate signed install, upgrade and removal on Windows. |

Allow **11–20 further engineering days** after the read-only shell if the host feasibility check succeeds. Certificate procurement and external signing approvals are outside this estimate.
