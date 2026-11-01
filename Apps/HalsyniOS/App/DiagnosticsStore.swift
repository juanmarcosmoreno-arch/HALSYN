import Foundation
import MetricKit
import Observation

/// Informes de cuelgues y cierres de la app que entrega iOS (MetricKit). Se
/// guardan en este iPhone y se pueden compartir desde Perfil › Diagnóstico:
/// traen la pila de llamadas, así se ve dónde se trabó sin tener que adivinar.
@MainActor
@Observable
final class DiagnosticsStore: NSObject {
    static let shared = DiagnosticsStore()
    static let maximumReports = 20

    struct Report: Identifiable, Hashable {
        let url: URL
        let date: Date
        let crashes: Int
        let hangs: Int
        let other: Int
        var id: URL { url }
    }

    private(set) var reports: [Report] = []
    @ObservationIgnored private let directory: URL

    private override init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        super.init()
        reload()
    }

    /// Empieza a recibir informes (al arrancar la app).
    func start() {
        MXMetricManager.shared.add(self)
        // Los que iOS ya tenía guardados de antes.
        save(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func deleteAll() {
        for report in reports { try? FileManager.default.removeItem(at: report.url) }
        reload()
    }

    fileprivate func save(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let other = (payload.cpuExceptionDiagnostics?.count ?? 0) + (payload.diskWriteExceptionDiagnostics?.count ?? 0)
            guard crashes + hangs + other > 0 else { continue }
            let stamp = Int(payload.timeStampEnd.timeIntervalSince1970)
            let name = [String(stamp), "\(crashes)c", "\(hangs)h", "\(other)o"].joined(separator: "-")
            let url = directory.appendingPathComponent(name).appendingPathExtension("json")
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try? payload.jsonRepresentation().write(to: url, options: .atomic)
        }
        prune()
        reload()
    }

    private func prune() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let sorted = files.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in sorted.dropFirst(Self.maximumReports) { try? FileManager.default.removeItem(at: old) }
    }

    private func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        reports = files.compactMap(Self.report(for:)).sorted { $0.date > $1.date }
    }

    /// "1730000000-1c-0h-0o.json" → fecha y recuentos.
    private static func report(for url: URL) -> Report? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard parts.count == 4, let stamp = TimeInterval(parts[0]),
              let crashes = Int(parts[1].dropLast()), let hangs = Int(parts[2].dropLast()), let other = Int(parts[3].dropLast()) else { return nil }
        return Report(url: url, date: Date(timeIntervalSince1970: stamp), crashes: crashes, hangs: hangs, other: other)
    }
}

extension DiagnosticsStore: MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { @MainActor in self.save(payloads) }
    }
}
