import Foundation
import MetricKit
import SwiftUI

/// What happened when the game last stopped without being closed: where it was (opening a world, reading the
/// save, the first frame...), how much memory it used then, and the system's own crash and hang reports
/// (MetricKit hands those to the app at its next launch). All of it stays on the device; the player can
/// look at it and share it from More → Diagnostics.
final class Diagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = Diagnostics()
    private let d = UserDefaults.standard
    static var dir: URL { GameModel.documents.appendingPathComponent("diagnostics", isDirectory: true) }

    /// Set at launch: the last session ended without the app being closed (a crash, or the system ending it).
    private(set) var lastEndedAbruptly = false
    private(set) var lastPhase = ""
    private(set) var lastFootprintMB = 0
    private(set) var lastPeakMB = 0
    private var peakMB = 0

    func start() {
        try? FileManager.default.createDirectory(at: Diagnostics.dir, withIntermediateDirectories: true)
        lastEndedAbruptly = d.object(forKey: "diag.cleanExit") != nil && !d.bool(forKey: "diag.cleanExit")
        lastPhase = d.string(forKey: "diag.phase") ?? ""
        lastFootprintMB = d.integer(forKey: "diag.mb")
        lastPeakMB = d.integer(forKey: "diag.peak")
        if lastEndedAbruptly { record(note: "previous session ended abruptly in phase '\(lastPhase)' at \(lastFootprintMB) MB (peak \(lastPeakMB) MB)") }
        d.set(false, forKey: "diag.cleanExit")
        d.set(0, forKey: "diag.peak")
        MXMetricManager.shared.add(self)
    }

    /// The app is going to the background or closing normally.
    func cleanExit() { d.set(true, forKey: "diag.cleanExit") }
    /// Back in front: not closed after all.
    func resumed() { d.set(false, forKey: "diag.cleanExit") }

    /// Where the game is now (kept so a crash can be told where it happened).
    func phase(_ p: String) {
        let mb = Diagnostics.footprintMB()
        peakMB = max(peakMB, mb)
        d.set(p, forKey: "diag.phase"); d.set(mb, forKey: "diag.mb"); d.set(peakMB, forKey: "diag.peak")
    }

    /// Sampled every few seconds while playing.
    func sample() {
        let mb = Diagnostics.footprintMB()
        peakMB = max(peakMB, mb)
        // written only when it has moved (this is called four times a second)
        guard abs(mb - lastWritten) >= 8 else { return }
        lastWritten = mb
        d.set(mb, forKey: "diag.mb"); d.set(peakMB, forKey: "diag.peak")
    }
    private var lastWritten = -100

    /// The memory the system counts against the app, MB.
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : 0
    }

    // MARK: the system's reports

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            let stamp = Int(p.timeStampEnd.timeIntervalSince1970)
            try? p.jsonRepresentation().write(to: Diagnostics.dir.appendingPathComponent("diagnostic-\(stamp).json"))
            var lines: [String] = []
            for c in p.crashDiagnostics ?? [] {
                lines.append("crash: \(c.exceptionType.map { "\($0)" } ?? "?") signal \(c.signal.map { "\($0)" } ?? "?") \(c.terminationReason ?? "") \(c.virtualMemoryRegionInfo ?? "")")
            }
            for h in p.hangDiagnostics ?? [] { lines.append("hang: \(h.hangDuration)") }
            for r in p.diskWriteExceptionDiagnostics ?? [] { lines.append("disk writes: \(r.totalWritesCaused)") }
            if !lines.isEmpty { record(note: lines.joined(separator: "\n")) }
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: .diagnosticsArrived, object: nil) }
    }

    func record(note: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(note)\n"
        let u = Diagnostics.dir.appendingPathComponent("log.txt")
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: u) }
    }

    /// The notes so far (newest last) and the report files.
    func log() -> String { (try? String(contentsOf: Diagnostics.dir.appendingPathComponent("log.txt"), encoding: .utf8)) ?? "" }
    func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: Diagnostics.dir, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// What a player is told at launch after an abrupt end.
    var launchNotice: String? {
        guard lastEndedAbruptly else { return nil }
        let where_ = Diagnostics.phaseName(lastPhase)
        return String(format: L("上次在「%@」时意外退出（当时内存 %d MB，最高 %d MB）。原因已记录在 更多 → 诊断。", "Last time the game stopped unexpectedly while %@ (memory %d MB, peak %d MB). See More → Diagnostics."),
                      where_, lastFootprintMB, lastPeakMB)
    }

    static func phaseName(_ p: String) -> String {
        switch p {
        case "open:index": return L("打开世界：读取存档", "opening a world: reading the save")
        case "open:decode": return L("打开世界：解析存档", "opening a world: decoding the save")
        case "open:restore": return L("打开世界：恢复世界", "opening a world: restoring it")
        case "open:scene": return L("打开世界：准备画面", "opening a world: preparing the view")
        case "play": return L("游戏中", "playing")
        case "save": return L("保存中", "saving")
        case "map": return L("打开地图", "opening the map")
        case "menu": return L("在菜单", "in the menu")
        default: return p.isEmpty ? L("未知", "unknown") : p
        }
    }
}

extension Notification.Name { static let diagnosticsArrived = Notification.Name("diagnosticsArrived") }

/// More → Diagnostics: the notes, the system's reports, and a button to share them.
struct DiagnosticsPanel: View {
    @EnvironmentObject var model: GameModel
    @State private var text = Diagnostics.shared.log()

    var body: some View {
        GlassSheet(title: L("诊断", "Diagnostics"), subtitle: String(format: L("当前内存 %d MB", "Memory now %d MB"), Diagnostics.footprintMB()), close: { model.showDiagnostics = false }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(text.isEmpty ? L("还没有记录。闪退后再次打开游戏，系统的闪退报告会出现在这里。", "Nothing recorded yet. After a crash, the system's report appears here when the game is opened again.") : text)
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                let files = Diagnostics.shared.files()
                if !files.isEmpty {
                    ShareLink(items: files) { Label(L("分享诊断文件", "Share diagnostic files"), systemImage: "square.and.arrow.up") }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .diagnosticsArrived)) { _ in text = Diagnostics.shared.log() }
    }
}
