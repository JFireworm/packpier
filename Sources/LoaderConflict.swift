import Foundation
import Darwin

enum LoaderConflict {
    static func running() -> Bool {
        let ignored = Set([getpid(), getppid()])
        let uid = getuid()
        let stride = MemoryLayout<pid_t>.stride
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard bytes > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / stride + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_UID_ONLY), uid, buffer.baseAddress, Int32(buffer.count))
        }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(max(0, Int(count) / stride)) where pid > 0 && !ignored.contains(pid) {
            let length = path.withUnsafeMutableBytes { buffer in
                proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
            }
            guard length > 0 else { continue }
            let executable = String(cString: path)
            if isLoader(executable) { return true }
            if executable.hasSuffix("/node"), runsWindowHost(pid) { return true }
        }
        return false
    }

    static func isLoader(_ executable: String) -> Bool {
        let path = URL(fileURLWithPath: executable)
        return ["packpier-codex-loader", "window-host.mjs", "codex-tweaks-backend"].contains(path.lastPathComponent)
            || (executable.hasSuffix("/Contents/Helpers/node") && executable.contains("/Packpier"))
            || executable.hasSuffix("/Contents/MacOS/Packpier")
    }

    private static func runsWindowHost(_ pid: pid_t) -> Bool {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return false }
        var buffer = [UInt8](repeating: 0, count: size)
        let status = buffer.withUnsafeMutableBytes { sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) }
        guard status == 0, size > MemoryLayout<Int32>.size else { return false }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc > 1 else { return false }
        // The buffer starts with argc and a NUL-terminated executable path. Environment follows argv.
        let process = buffer.prefix(size).dropFirst(MemoryLayout<Int32>.size)
        let argv = process.drop(while: { $0 != 0 }).drop(while: { $0 == 0 })
        return argv.split(separator: 0, maxSplits: argc, omittingEmptySubsequences: false)
            .prefix(argc).dropFirst().contains {
                let argument = String(decoding: $0, as: UTF8.self)
                return argument == "window-host.mjs" || argument.hasSuffix("/window-host.mjs")
            }
    }
}
