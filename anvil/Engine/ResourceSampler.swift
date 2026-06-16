import Foundation
import Darwin

/// Mede o consumo durante a build. CPU é do **sistema** (instantânea), porque o
/// trabalho pesado de `xcodebuild` roda no daemon `XCBBuildService` — fora da
/// árvore do processo que disparamos. Memória é a soma RSS da árvore (atribuível).
/// Mantém estado entre amostras (ticks anteriores) → é classe.
final class ResourceSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var prevBusy = 0.0
    private var prevTotal = 0.0
    private var hasPrev = false
    private var lastCPU = 0.0

    func sample(rootPID: Int32) -> ProcessMetrics? {
        ProcessMetrics(cpu: systemCPU(), memoryMB: treeRSS(rootPID: rootPID))
    }

    /// %CPU do sistema (0–100) por delta de ticks entre amostras.
    private func systemCPU() -> Double {
        var size = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        lock.lock(); defer { lock.unlock() }
        guard kr == KERN_SUCCESS else { return lastCPU }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { prevBusy = busy; prevTotal = total; hasPrev = true }

        guard hasPrev else { return 0 }
        let dBusy = busy - prevBusy
        let dTotal = total - prevTotal
        guard dTotal > 0 else { return lastCPU }
        lastCPU = max(0, min(100, dBusy / dTotal * 100))
        return lastCPU
    }

    /// Soma RSS (MB) da subárvore enraizada em `rootPID`.
    private func treeRSS(rootPID: Int32) -> Double {
        guard let out = runPS() else { return 0 }
        var rssOf: [Int32: Double] = [:]
        var children: [Int32: [Int32]] = [:]
        for raw in out.split(separator: "\n") {
            let f = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
            guard f.count >= 3, let pid = Int32(f[0]), let ppid = Int32(f[1]), let rss = Double(f[2]) else { continue }
            rssOf[pid] = rss
            children[ppid, default: []].append(pid)
        }
        var stack = [rootPID]; var seen = Set<Int32>(); var total = 0.0
        while let cur = stack.popLast() {
            guard seen.insert(cur).inserted else { continue }
            total += rssOf[cur] ?? 0
            if let kids = children[cur] { stack.append(contentsOf: kids) }
        }
        return total / 1024.0
    }

    private func runPS() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,ppid=,rss="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
