import HalsynCore
import SwiftUI
import UIKit

/// Lee de Salud la ruta y el pulso de cada carrera **una sola vez** y alimenta
/// los récords, el análisis aeróbico y los recorridos repetidos.
@MainActor
enum RunDetailPipeline {
    /// Cada cuántas carreras leídas de Salud se guarda el avance.
    static let batchSize = 40
    private static var running = false

    /// Lee todo lo que falta, de la más nueva a la más vieja. Se recorre el historial
    /// completo en la misma pasada: con el historial a medias, una carrera puede
    /// figurar como récord solo porque todavía no se leyeron las anteriores.
    static func refresh(runs allRuns: [WorkoutSummary], provider: any HealthDataProviding) async {
        // Con el iPhone bloqueado Salud no entrega datos: se leería todo vacío.
        guard !running, UIApplication.shared.isProtectedDataAvailable else { return }
        running = true
        defer { running = false }
        let runs = WorkoutQualityStore.shared.clean(allRuns.filter(\.activity.isRun)).sorted { $0.start > $1.start }
        let records = RunRecordStore.shared, aerobic = AerobicStore.shared, routes = RouteStore.shared
        let ids = Set(runs.map(\.id))
        records.setValid(ids)
        aerobic.setValid(ids)
        routes.setRuns(runs)
        var fetched = 0, changed = false
        for run in runs {
            let outdoor = run.activity == .outdoorRun
            let needsRecord = records.needs(run.id)
            let needsAerobic = outdoor && aerobic.needs(run.id)
            let needsRoute = outdoor && routes.needs(run.id)
            guard needsRecord || needsAerobic || needsRoute else { continue }
            var detail: WorkoutDetailData?
            if outdoor {
                detail = await provider.workoutDetail(for: run)
                // Si se canceló a mitad de la lectura, el detalle puede venir vacío: no se guarda.
                if Task.isCancelled { break }
                fetched += 1
            }
            if needsRecord { records.ingest(run, detail: detail) }
            if let detail, needsAerobic { aerobic.ingest(run, detail: detail) }
            if let detail, needsRoute { routes.ingest(run, detail: detail) }
            changed = true
            if outdoor, fetched % batchSize == 0 {
                // Avance guardado y pantalla al día sin esperar al final.
                aerobic.save()
                routes.save()
                records.save()
                routes.regroup()
                await Task.yield()
            }
        }
        if changed {
            aerobic.save()
            routes.save()
        }
        // Siempre: la tabla del reloj se actualiza también si solo cambió qué carreras son válidas.
        records.save()
        routes.regroup()
    }
}

/// Huellas de recorrido de cada carrera y los grupos de recorridos repetidos.
@MainActor
@Observable
final class RouteStore {
    static let shared = RouteStore()

    private(set) var fingerprints: [UUID: RouteFingerprint] = [:]
    private(set) var groups: [RouteGroup] = []
    private(set) var validIDs: Set<UUID> = []
    /// Resúmenes de las carreras válidas (para comparar tiempos y pulso).
    private(set) var runs: [UUID: WorkoutSummary] = [:]
    @ObservationIgnored private var skipped: Set<UUID> = []
    @ObservationIgnored private var unread: Set<UUID> = []
    @ObservationIgnored private let url: URL
    /// Carreras ya leídas sin ruta útil: no se vuelven a leer de Salud en cada arranque.
    private static let skippedKey = "halsyn.routeSkipped"

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        url = base.appendingPathComponent("route-fingerprints.json")  // nolocalize
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([RouteFingerprint].self, from: $0) } ?? []
        fingerprints = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        validIDs = Set(fingerprints.keys)
        skipped = Set((UserDefaults.standard.stringArray(forKey: Self.skippedKey) ?? []).compactMap(UUID.init(uuidString:)))
        regroup()
    }

    func setRuns(_ list: [WorkoutSummary]) {
        validIDs = Set(list.map(\.id))
        runs = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func needs(_ id: UUID) -> Bool { fingerprints[id] == nil && !skipped.contains(id) && !unread.contains(id) }

    func comparison(for id: UUID) -> RouteComparison? {
        group(for: id).flatMap { RouteComparisonEngine.compare(id, group: $0, runs: runs) }
    }

    func ingest(_ run: WorkoutSummary, detail: WorkoutDetailData) {
        if let fingerprint = RouteMatching.fingerprint(id: run.id, date: run.start, route: detail.route) {
            fingerprints[run.id] = fingerprint
        } else if detail.route.isEmpty && detail.heartRate.isEmpty {
            // Sin nada de nada puede ser un fallo de lectura: se reintenta en otro arranque.
            unread.insert(run.id)
        } else {
            skipped.insert(run.id)
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(Array(fingerprints.values)) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
        UserDefaults.standard.set(skipped.map(\.uuidString), forKey: Self.skippedKey)
    }

    /// Vuelve a agrupar (también cuando entra una carrera más vieja que la referencia).
    func regroup() {
        groups = RouteMatching.groups(fingerprints.values.filter { validIDs.contains($0.id) })
            .sorted { $0.members.count > $1.members.count }
    }

    func group(for id: UUID) -> RouteGroup? {
        groups.first { $0.members.contains(id) }
    }
}
