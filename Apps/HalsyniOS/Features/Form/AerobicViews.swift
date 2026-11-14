import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

/// Análisis aeróbico de cada carrera (se calcula una vez y se guarda).
@MainActor
@Observable
final class AerobicStore {
    static let shared = AerobicStore()
    static let key = "halsyn.aerobicObservations"

    private(set) var observations: [UUID: AerobicRunObservation]
    private(set) var validIDs: Set<UUID> = []
    /// Carreras ya revisadas sin tramos útiles (cinta, sin GPS o sin pulso).
    @ObservationIgnored private var skipped: Set<UUID> = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([AerobicRunObservation].self, from: $0) } ?? []
        observations = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        validIDs = Set(observations.keys)
    }

    /// Carreras válidas (sin duplicados ni excluidas), de la más vieja a la más nueva.
    var valid: [AerobicRunObservation] {
        observations.values.filter { validIDs.contains($0.id) }.sorted { $0.date < $1.date }
    }

    func refresh(runs allRuns: [WorkoutSummary], provider: any HealthDataProviding) async {
        await RunDetailPipeline.refresh(runs: allRuns, provider: provider)
    }

    func setValid(_ ids: Set<UUID>) { validIDs = ids }
    func needs(_ id: UUID) -> Bool { observations[id] == nil && !skipped.contains(id) }

    func ingest(_ run: WorkoutSummary, detail: WorkoutDetailData) {
        if let observation = AerobicAnalysis.observe(id: run.id, date: run.start, route: detail.route, heartRate: detail.heartRate) {
            observations[run.id] = observation
        } else {
            skipped.insert(run.id)
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(Array(observations.values)) { defaults.set(data, forKey: Self.key) }
    }
}

enum AerobicText {
    static func pace(_ secondsPerKilometer: Double, unit: UnitSystem) -> String {
        Pace(secondsPerKilometer: secondsPerKilometer).formatted(in: unit) + " " + unit.paceUnitSymbol  // nolocalize
    }

    static func unavailable(_ reason: AerobicUnavailable) -> String {
        switch reason {
        case .notEnoughRuns: String(localized: "Hacen falta al menos 3 carreras al aire libre con GPS y pulso en el período, con tramos a ritmo estable.")
        case .outsideObservedRange: String(localized: "En el período no corriste a ese pulso: no se estima fuera de lo que observaste.")
        case .noRelationship: String(localized: "Tus datos no muestran una relación clara entre pulso y velocidad todavía.")
        }
    }

    /// "9 s/km más rápido que hace 8 semanas" o "sin cambio claro".
    static func trend(_ trend: FixedHeartRateTrend, unit: UnitSystem) -> String? {
        guard let change = trend.change, let verdict = trend.verdict else { return nil }
        let secondsText = String(Int(abs(change).rounded()))
        switch verdict {
        case .faster: return String(localized: "\(secondsText) s/km más rápido que hace 8 semanas")
        case .slower: return String(localized: "\(secondsText) s/km más lento que hace 8 semanas")
        case .unclear: return String(localized: "Sin cambio claro frente a hace 8 semanas (la diferencia cabe en la incertidumbre)")
        }
    }
}

/// Fila de Rendimiento con el dato principal.
struct AerobicAreaLink: View {
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @AppStorage("halsyn.aerobic.heartRate") private var target = 150.0

    var body: some View {
        FormAreaLink(title: "Capacidad aeróbica", subtitle: subtitle, systemImage: "heart.text.square") {
            AerobicView()
        }
    }

    private var subtitle: String {
        let observations = AerobicStore.shared.valid
        let targetText = String(Int(target))
        switch AerobicAnalysis.trend(at: target, observations: observations, today: .now, calendar: .current) {
        case let .success(trend):
            let paceText = AerobicText.pace(trend.current.pace, unit: unitSystem)
            if let change = AerobicText.trend(trend, unit: unitSystem), trend.verdict != .unclear {
                return String(localized: "Ritmo a \(targetText) lpm: \(paceText) · \(change)")
            }
            return String(localized: "Ritmo a \(targetText) lpm: \(paceText)")
        case .failure:
            return String(localized: "¿Corres más rápido con el mismo pulso?")
        }
    }
}

/// Capacidad aeróbica: ritmo a pulso fijo, eficiencia y desacople.
struct AerobicView: View {
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @AppStorage("halsyn.aerobic.heartRate") private var target = 150.0
    private var store: AerobicStore { .shared }

    private struct HistoryPoint: Identifiable {
        let id = UUID()
        let date: Date
        let pace: Double
        let fastest: Double
        let slowest: Double
    }

    var body: some View {
        let observations = store.valid
        HalsynScreen {
            Text("¿Corres más rápido con el mismo esfuerzo del corazón?")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
                .padding(.top, HalsynSpacing.s)
            paceCard(observations)
            efficiencyCard(observations)
            decouplingCard(observations)
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    Text("Cómo se calcula")
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    ExpandableText("Solo carreras al aire libre con GPS y pulso, sin duplicados. De cada una se usan los tramos de 200 m a ritmo estable: después del calentamiento, sin aceleraciones (ritmo a menos de un 8 % de los tramos vecinos), casi llanos y con el pulso tomado 30 s después, porque el corazón tarda en responder. El ritmo a un pulso sale de una recta velocidad–pulso con las carreras de los últimos 28 días, solo dentro de los pulsos que corriste (no se extrapola); la incertidumbre cuenta cada carrera como una observación. Se compara con el mismo cálculo de hace 8 semanas y solo se habla de cambio si supera esa incertidumbre. Eficiencia = velocidad (m/min) ÷ pulso. Desacople = cuánto cae la eficiencia de la primera a la segunda mitad (Friel), solo en carreras regulares de 30 min o más. El calor, la hidratación, el cansancio y el terreno también influyen: es orientativo, no un diagnóstico.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                    Text(verbatim: "AerobicAnalysis \(AerobicAnalysis.version)")  // nolocalize
                        .font(.caption2.monospaced())
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .navigationTitle("Capacidad aeróbica")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Ritmo a pulso fijo

    private func paceCard(_ observations: [AerobicRunObservation]) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Ritmo a pulso fijo", eyebrow: HalsynLexicon.puls.rawValue)
                Picker("Pulso", selection: $target) {
                    ForEach(AerobicAnalysis.targets, id: \.self) { value in
                        Text(verbatim: "\(Int(value))").tag(value)  // nolocalize
                    }
                }
                .pickerStyle(.segmented)
                switch AerobicAnalysis.trend(at: target, observations: observations, today: .now, calendar: .current) {
                case let .success(trend):
                    let rangeText = AerobicText.pace(trend.current.fastest, unit: unitSystem) + "–" + AerobicText.pace(trend.current.slowest, unit: unitSystem)  // nolocalize
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: AerobicText.pace(trend.current.pace, unit: unitSystem))
                            .font(.halsynMetricValue)
                            .foregroundStyle(.halsynPrimaryText)
                        Spacer()
                        let runsText = String(trend.current.runs)
                        Text("\(runsText) carreras · 28 días")
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    Text("Rango probable: \(rangeText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.halsynSecondaryText)
                    if let change = AerobicText.trend(trend, unit: unitSystem) {
                        Label(change, systemImage: trend.verdict == .faster ? "arrow.up.right" : (trend.verdict == .slower ? "arrow.down.right" : "equal"))
                            .font(.halsynCaption.weight(.semibold))
                            .foregroundStyle(trend.verdict == .faster ? Color.halsynPositive : (trend.verdict == .slower ? Color.halsynCaution : Color.halsynSecondaryText))
                    } else {
                        Text("Todavía no hay datos de hace 8 semanas para comparar.")
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    history(observations)
                case let .failure(error):
                    Text(verbatim: AerobicText.unavailable(error.reason))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// El ritmo a ese pulso cada 2 semanas (con los 28 días anteriores a cada fecha).
    @ViewBuilder
    private func history(_ observations: [AerobicRunObservation]) -> some View {
        let calendar = Calendar.current
        let points: [HistoryPoint] = (0..<12).reversed().compactMap { step in
            guard let end = calendar.date(byAdding: .day, value: -14 * step, to: .now),
                  let start = calendar.date(byAdding: .day, value: -AerobicAnalysis.windowDays, to: end),
                  case let .success(estimate) = AerobicAnalysis.paceAt(target, observations: observations, from: start, to: end) else { return nil }
            return HistoryPoint(date: end, pace: estimate.pace / 60, fastest: estimate.fastest / 60, slowest: estimate.slowest / 60)
        }
        if points.count >= 2 {
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Fecha", point.date), yStart: .value("Rápido", point.fastest), yEnd: .value("Lento", point.slowest))
                        .foregroundStyle(Color.halsynChart.opacity(0.15))
                    LineMark(x: .value("Fecha", point.date), y: .value("Ritmo", point.pace))
                        .foregroundStyle(Color.halsynChart)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Fecha", point.date), y: .value("Ritmo", point.pace))
                        .foregroundStyle(Color.halsynChart)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) { Text(verbatim: HalsynFormat.duration(minutes * 60)) }
                    }
                }
            }
            .frame(height: 150)
            Text("Más arriba es más rápido. La banda es la incertidumbre de cada estimación.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    // MARK: Eficiencia

    private func efficiencyCard(_ observations: [AerobicRunObservation]) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Eficiencia", eyebrow: HalsynLexicon.fart.rawValue)
                if let summary = AerobicAnalysis.efficiency(observations, today: .now, calendar: .current) {
                    ForEach(summary.windows, id: \.days) { window in
                        LabeledContent {
                            Text(verbatim: HalsynFormat.decimal(window.mean, fractionDigits: 2))
                                .monospacedDigit()
                        } label: {
                            let runsText = String(window.runs)
                            if let days = window.days {
                                let daysText = String(days)
                                Text("Últimos \(daysText) días (\(runsText) carreras)")
                            } else {
                                Text("Todo (\(runsText) carreras)")
                            }
                        }
                        .font(.halsynCaption)
                    }
                    if let change = summary.change28 {
                        let changeText = (change >= 0 ? "+" : "−") + HalsynFormat.decimal(abs(change), fractionDigits: 1) + " %"  // nolocalize
                        Text(summary.changeIsClear
                             ? LocalizedStringKey("Últimos 28 días frente a los 28 anteriores: \(changeText). Supera tu variación habitual.")
                             : LocalizedStringKey("Últimos 28 días frente a los 28 anteriores: \(changeText). Dentro de tu variación habitual: todavía no es un cambio claro."))
                            .font(.caption2)
                            .foregroundStyle(summary.changeIsClear ? (change > 0 ? Color.halsynPositive : Color.halsynCaution) : Color.halsynSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Metros por minuto por cada latido en los tramos estables. Más alto = más velocidad con el mismo pulso.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                } else {
                    Text(verbatim: AerobicText.unavailable(.notEnoughRuns))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
    }

    // MARK: Desacople

    private func decouplingCard(_ observations: [AerobicRunObservation]) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Desacople en carreras largas", eyebrow: HalsynLexicon.puls.rawValue)
                if let summary = AerobicAnalysis.decoupling(observations, today: .now, calendar: .current) {
                    let latestText = HalsynFormat.decimal(summary.latest.value, fractionDigits: 1) + " %"  // nolocalize
                    let dateText = summary.latest.day.formatted(date: .abbreviated, time: .omitted)
                    Text("Última: \(latestText) (\(dateText))")
                        .font(.halsynCaption.weight(.semibold))
                    if let median = summary.median28 {
                        let medianText = HalsynFormat.decimal(median, fractionDigits: 1) + " %"  // nolocalize
                        let runsText = String(summary.runs28)
                        Text("Mediana de los últimos 28 días: \(medianText) (\(runsText) carreras)")
                            .font(.halsynCaption)
                    }
                    if summary.series.count >= 2 {
                        Chart {
                            ForEach(summary.series, id: \.day) { point in
                                PointMark(x: .value("Fecha", point.day), y: .value("%", point.value))
                                    .foregroundStyle(Color.halsynChart)
                            }
                        }
                        .frame(height: 120)
                    }
                    Text("Cuánto cae la eficiencia de la primera a la segunda mitad. Más bajo = el corazón sostiene mejor el ritmo. Por debajo de un 5 % suele considerarse bajo, pero el calor, la duración y el terreno lo cambian: compáralo con tus propias carreras parecidas.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Se calcula en carreras continuas y regulares de 30 min o más al aire libre. Todavía no hay ninguna.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
    }
}
