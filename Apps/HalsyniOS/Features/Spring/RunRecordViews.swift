import HalsynCore
import HalsynDesign
import SwiftUI

/// Récords de cada carrera (calculados una vez por entrenamiento y guardados).
/// Comparte con el reloj la tabla de las 3 mejores marcas de cada récord.
@MainActor
@Observable
final class RunRecordStore {
    static let shared = RunRecordStore()
    static let key = "halsyn.runRecordEntries"
    /// Carreras nuevas que se analizan en cada pasada (cada una lee su ruta de Salud).
    static let batchSize = 80

    private(set) var entries: [UUID: RunRecordEntry]
    /// Carreras válidas (sin duplicados ni excluidas) de la última pasada.
    private(set) var validIDs: Set<UUID> = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var refreshing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([RunRecordEntry].self, from: $0) } ?? []
        entries = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        validIDs = Set(entries.keys)
    }

    private var validEntries: [RunRecordEntry] {
        entries.values.filter { validIDs.contains($0.id) }
    }

    /// Calcula los récords de las carreras que faltan y actualiza la tabla del reloj.
    func refresh(runs allRuns: [WorkoutSummary], provider: any HealthDataProviding) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let runs = WorkoutQualityStore.shared.clean(allRuns.filter(\.activity.isRun))
        validIDs = Set(runs.map(\.id))
        let missing = runs.filter { entries[$0.id] == nil }.sorted { $0.start > $1.start }.prefix(Self.batchSize)
        for run in missing {
            var splits: [TimeInterval] = []
            var usesGPS = false
            if run.activity == .outdoorRun {
                let detail = await provider.workoutDetail(for: run)
                usesGPS = detail.route.count > 1
                splits = RunRecords.kilometerDurations(WorkoutAnalysis.splits(from: detail.route, splitDistance: 1000))
            }
            entries[run.id] = RunRecords.entry(id: run.id, date: run.start, distance: run.distanceMeters ?? 0, duration: run.duration, kilometerSplits: splits, usesGPS: usesGPS)
        }
        if !missing.isEmpty, let data = try? JSONEncoder().encode(Array(entries.values)) {
            defaults.set(data, forKey: Self.key)
        }
        RunSettingsStore.shared.shareRecords(RunRecords.board(validEntries))
    }

    /// Puestos de esta carrera el día que se corrió (frente a las anteriores).
    func placements(for id: UUID) -> [RunRecordPlacement] {
        guard validIDs.contains(id), let entry = entries[id] else { return [] }
        return RunRecords.placements(of: entry, among: validEntries)
    }

    /// Tus 3 mejores de cada récord, con la fecha.
    var podium: [(RunRecordCategory, [RunRecordBoard.Mark])] {
        let board = RunRecords.board(validEntries)
        return RunRecordCategory.allCases.compactMap { category in
            board.top[category].map { (category, $0) }
        }
    }
}

enum RunRecordText {
    static func title(_ category: RunRecordCategory) -> String {
        String(localized: String.LocalizationValue(category.title))
    }

    static func rank(_ rank: Int) -> String {
        switch rank {
        case 1: String(localized: "Récord")
        case 2: String(localized: "2.ª mejor")
        default: String(localized: "3.ª mejor")
        }
    }

    static func value(_ category: RunRecordCategory, _ value: Double, unit: UnitSystem) -> String {
        switch category {
        case .longestDistance: HalsynFormat.distance(meters: value, unit: unit) + " " + unit.distanceUnitSymbol  // nolocalize
        default: HalsynFormat.duration(value)
        }
    }

    /// «Récord · 5 km más rápidos · 24:51 (antes 25:10)».
    static func line(_ placement: RunRecordPlacement, unit: UnitSystem) -> String {
        var text = rank(placement.rank) + " · " + title(placement.category) + " · " + value(placement.category, placement.value, unit: unit)  // nolocalize
        if placement.isRecord, let previous = placement.previousBest {
            let previousText = value(placement.category, previous, unit: unit)
            text += " " + String(localized: "(antes \(previousText))")
        }
        return text
    }

    static func medal(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 0.85, green: 0.65, blue: 0.13)
        case 2: Color(red: 0.62, green: 0.64, blue: 0.68)
        default: Color(red: 0.72, green: 0.45, blue: 0.20)
        }
    }
}

/// Medalla en la fila del historial (el mejor puesto de esa carrera).
struct RunRecordBadge: View {
    let workoutID: UUID

    var body: some View {
        if let best = RunRecordStore.shared.placements(for: workoutID).map(\.rank).min() {
            Image(systemName: best == 1 ? "trophy.fill" : "medal.fill")
                .font(.caption)
                .foregroundStyle(RunRecordText.medal(best))
                .accessibilityLabel(Text(verbatim: RunRecordText.rank(best)))
        }
    }
}

/// Récords de una carrera en su detalle.
struct RunRecordCard: View {
    let workout: WorkoutSummary
    let unitSystem: UnitSystem

    var body: some View {
        let placements = RunRecordStore.shared.placements(for: workout.id)
        if !placements.isEmpty {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    Label("Récords", systemImage: "trophy")
                        .halsynEyebrowStyle()
                    ForEach(placements) { placement in
                        HStack(spacing: HalsynSpacing.s) {
                            Image(systemName: placement.isRecord ? "trophy.fill" : "medal.fill")
                                .foregroundStyle(RunRecordText.medal(placement.rank))
                            Text(verbatim: RunRecordText.line(placement, unit: unitSystem))
                                .font(.halsynCaption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    NavigationLink {
                        RunRecordsView()
                    } label: {
                        Text("Todos tus récords")
                            .font(.halsynCaption.weight(.semibold))
                    }
                    Text("Comparada con tus carreras anteriores a esta. Los tiempos son la mejor suma de kilómetros completos seguidos, con GPS (sin cinta).")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Tus 3 mejores de cada récord.
struct RunRecordsView: View {
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        Form {
            let podium = RunRecordStore.shared.podium
            if podium.isEmpty {
                Text("Todavía no hay récords: aparecen cuando tengas al menos dos carreras para comparar.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
            ForEach(Array(podium.enumerated()), id: \.offset) { _, item in
                let (category, marks) = item
                Section(RunRecordText.title(category)) {
                    ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                        LabeledContent {
                            Text(verbatim: RunRecordText.value(category, mark.value, unit: unitSystem))
                                .monospacedDigit()
                        } label: {
                            Label {
                                Text(mark.date, format: .dateTime.day().month(.abbreviated).year())
                            } icon: {
                                Image(systemName: index == 0 ? "trophy.fill" : "medal.fill")
                                    .foregroundStyle(RunRecordText.medal(index + 1))
                            }
                        }
                    }
                }
            }
            Section {
                Text("Kilómetro, 5 km y 10 km: la mejor suma de kilómetros completos seguidos de cada carrera al aire libre con GPS (las de cinta no cuentan para los tiempos; un kilómetro por debajo de 2:30 se toma como salto del GPS). Distancia y duración: de la carrera entera. Sin duplicados ni carreras que excluiste. El reloj te avisa al terminar si una carrera queda 1.ª, 2.ª o 3.ª.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .navigationTitle("Récords")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
    }
}
