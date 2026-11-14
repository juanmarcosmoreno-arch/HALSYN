import HalsynCore
import HalsynDesign
import SwiftUI

/// Récords de cada carrera (calculados una vez por entrenamiento y guardados).
/// Comparte con el reloj la tabla de las 3 mejores marcas de cada récord.
@MainActor
@Observable
final class RunRecordStore {
    static let shared = RunRecordStore()
    /// v2 (0.10.0 (126)): mejores esfuerzos en cualquier tramo; las de la v1 (km enteros) se recalculan.
    static let key = "halsyn.runRecordEntries.v2"
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

    var validEntries: [RunRecordEntry] {
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
            var timeline: [EffortPoint] = []
            var heartRate: [HeartRatePoint] = []
            var routeStart: Date?
            if run.activity == .outdoorRun {
                let detail = await provider.workoutDetail(for: run)
                timeline = RunRecords.timeline(from: detail.route)
                heartRate = detail.heartRate
                routeStart = detail.route.map(\.timestamp).min()
            }
            var entry = RunRecords.entry(id: run.id, date: run.start, distance: run.distanceMeters ?? 0, duration: run.duration, timeline: timeline, recordedDistance: run.distanceMeters)
            // Pulso medio de cada mejor esfuerzo (desde el primer punto de la ruta).
            if let starts = entry.starts, let routeStart {
                var rates: [RunRecordCategory: Double] = [:]
                for (category, start) in starts {
                    if let duration = entry.values[category], let bpm = RunRecords.heartRate(heartRate, runStart: routeStart, start: start, duration: duration) {
                        rates[category] = bpm
                    }
                }
                entry.heartRates = rates.isEmpty ? nil : rates
            }
            entries[run.id] = entry
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

/// Medallita en la fila del historial: oro si fue récord, plata si fue la
/// 2.ª mejor (el 3.er puesto se ve en el detalle, no en la lista).
struct RunRecordBadge: View {
    let workoutID: UUID

    var body: some View {
        if let best = RunRecordStore.shared.placements(for: workoutID).map(\.rank).min(), best <= 2 {
            Image(systemName: "medal.fill")
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
                        RunRecordMarkRow(category: category, mark: mark, rank: index + 1, unit: unitSystem)
                    }
                    NavigationLink {
                        RunRecordDetailView(category: category)
                    } label: {
                        Text("Este año, 90 días y cronología")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynAccentText)
                    }
                }
            }
            Section {
                Text("Mejores esfuerzos: el tramo continuo más rápido de cada distancia en cualquier parte de una carrera al aire libre con GPS (un 5 km puede estar dentro de una carrera de 8 km). El tiempo incluye las pausas: quitarlas inventaría un esfuerzo continuo que no existió. No cuentan las carreras en cinta, las que tienen una distancia GPS que se aparta más de un 8 % de la de Salud ni los tramos más rápidos que 2:30 /km (saltos del GPS). Sin 100 ni 200 m: el error del GPS sería de segundos. Distancia y duración: de la carrera entera. Sin duplicados ni carreras que excluiste. El reloj te avisa al terminar si una carrera queda 1.ª, 2.ª o 3.ª.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                Text(verbatim: "RunRecords \(RunRecords.version)")  // nolocalize
                    .font(.caption2.monospaced())
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .navigationTitle("Récords")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
    }
}

/// Una marca con su fecha, el pulso del tramo y si fue en un test o una competición.
struct RunRecordMarkRow: View {
    let category: RunRecordCategory
    let mark: RunRecordBoard.Mark
    let rank: Int?
    let unit: UnitSystem

    var body: some View {
        let entry = RunRecordStore.shared.entries[mark.id]
        let marked = FitnessStore.shared.results.first { $0.workoutID == mark.id }?.kind
        LabeledContent {
            Text(verbatim: RunRecordText.value(category, mark.value, unit: unit))
                .monospacedDigit()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(mark.date, format: .dateTime.day().month(.abbreviated).year())
                    let details = [
                        entry?.heartRates?[category].map { "\(Int($0.rounded())) lpm" },  // nolocalize
                        marked.map { $0 == .race ? String(localized: "en competición") : String(localized: "en un test") },
                    ].compactMap { $0 }
                    if !details.isEmpty {
                        Text(verbatim: details.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
            } icon: {
                if let rank {
                    Image(systemName: rank == 1 ? "trophy.fill" : "medal.fill")
                        .foregroundStyle(RunRecordText.medal(rank))
                } else {
                    Image(systemName: "calendar")
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
    }
}

/// Una distancia: récord del año, de 90 días y cómo fue bajando la marca.
struct RunRecordDetailView: View {
    let category: RunRecordCategory
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        let entries = RunRecordStore.shared.validEntries
        let calendar = Calendar.current
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: .now)) ?? .now
        let ninety = calendar.date(byAdding: .day, value: -90, to: .now) ?? .now
        let progression = RunRecords.progression(category, entries: entries)
        Form {
            Section {
                if let mark = RunRecords.bests(entries, from: yearStart)[category] {
                    RunRecordMarkRow(category: category, mark: mark, rank: nil, unit: unitSystem)
                } else {
                    Text("Sin marca este año.").font(.halsynCaption).foregroundStyle(.halsynSecondaryText)
                }
            } header: {
                Text("Mejor del año")
            }
            Section {
                if let mark = RunRecords.bests(entries, from: ninety)[category] {
                    RunRecordMarkRow(category: category, mark: mark, rank: nil, unit: unitSystem)
                } else {
                    Text("Sin marca en los últimos 90 días.").font(.halsynCaption).foregroundStyle(.halsynSecondaryText)
                }
            } header: {
                Text("Mejor de los últimos 90 días")
            }
            if !progression.isEmpty {
                Section {
                    ForEach(Array(progression.enumerated().reversed()), id: \.offset) { index, mark in
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(verbatim: RunRecordText.value(category, mark.value, unit: unitSystem))
                                    .monospacedDigit()
                                if index > 0 {
                                    let previous = progression[index - 1].value
                                    let gain = category.higherIsBetter ? mark.value - previous : previous - mark.value
                                    // Tiempos: cuánto bajó; distancia y duración: cuánto subió.
                                    Text(verbatim: (category.higherIsBetter ? "+" : "−") + RunRecordText.value(category, gain, unit: unitSystem))  // nolocalize
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.halsynPositive)
                                }
                            }
                        } label: {
                            Text(mark.date, format: .dateTime.day().month(.abbreviated).year())
                        }
                    }
                    if let first = progression.first, let last = progression.last, progression.count > 1 {
                        let total = category.higherIsBetter ? last.value - first.value : first.value - last.value
                        let totalText = RunRecordText.value(category, total, unit: unitSystem)
                        Text("Mejora acumulada: \(totalText)")
                            .font(.halsynCaption.weight(.semibold))
                    }
                } header: {
                    Text("Cronología del récord")
                } footer: {
                    Text("Cada fila es una marca que superó a todas las anteriores.")
                }
            }
        }
        .navigationTitle(Text(verbatim: RunRecordText.title(category)))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
    }
}
