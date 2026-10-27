import Charts
import HalsynCore
import HalsynDesign
import Observation
import SwiftUI

/// Calcula y guarda la carga de entrenamiento (correr, caminar y bici) para
/// SPRING y CYKEL. Cada resumen vale para una clave (fuente de datos, recarga y
/// ajustes): con otra clave no se muestra uno viejo.
@MainActor
@Observable
final class TrainingLoadStore {
    static let shared = TrainingLoadStore()

    private(set) var summaries: [LoadMetric: (key: String, summary: TrainingLoadSummary)] = [:]
    /// FC en reposo, máximas y sexo usados en la carga por pulso.
    private(set) var inputs: HeartRateLoadInputs?

    func summary(_ metric: LoadMetric, key: String) -> TrainingLoadSummary? {
        summaries[metric].flatMap { $0.key == key ? $0.summary : nil }
    }

    func load(_ metric: LoadMetric, provider: any HealthDataProviding, settings: RunSettings, ftp: Double?, key: String) async {
        guard summaries[metric]?.key != key else { return }
        let runs = await provider.recentWorkouts(limit: 400)
        let rides = await provider.recentRides(limit: 400)
        let limit = Calendar.current.date(byAdding: .day, value: -TrainingLoadBuilder.historyLimitDays, to: .now) ?? .now
        var loads: [WorkoutLoad] = []
        var skipped = 0
        var usedInputs: HeartRateLoadInputs?
        switch metric {
        case .heartRate:
            let inputs = await heartRateInputs(provider: provider, settings: settings, runs: runs, rides: rides)
            let result = TrainingLoadCalculator.heartRateLoads((runs + rides).filter { $0.start >= limit }, inputs: inputs)
            loads = result.loads
            skipped = result.skipped
            usedInputs = inputs
        case .power:
            // Solo bici con medidor; sin FTP no hay TSS.
            for ride in rides where ride.start >= limit {
                guard let ftp, ride.averagePower != nil else {
                    skipped += 1
                    continue
                }
                let samples = await provider.ridePower(for: ride)
                guard let tss = PowerAnalysis.summary(samples)?.trainingStressScore(ftp: ftp) else {
                    skipped += 1
                    continue
                }
                loads.append(WorkoutLoad(workoutID: ride.id, date: ride.start, sport: .cycling, value: tss))
            }
        }
        // Una carga cancelada (cambio de pestaña) puede venir incompleta: no se guarda.
        guard !Task.isCancelled else { return }
        if let usedInputs { inputs = usedInputs }
        summaries[metric] = (key, TrainingLoadBuilder.build(loads: loads, metric: metric, skipped: skipped, today: .now, calendar: .current))
    }

    /// FC en reposo: la mediana de los últimos 30 días en Salud (o la de tus
    /// zonas). FC máxima: la de las zonas de cada deporte o la más alta registrada.
    private func heartRateInputs(provider: any HealthDataProviding, settings: RunSettings, runs: [WorkoutSummary], rides: [WorkoutSummary]) async -> HeartRateLoadInputs {
        let resting = await provider.dailySeries(.restingHeartRate, days: 30, endingOn: .now).values.map(\.value).sorted()
        let restingHeartRate = resting.isEmpty ? settings.zones.restingHeartRate : resting[resting.count / 2]
        var maxHeartRate: [WorkoutSport: Double] = [:]
        maxHeartRate[.running] = settings.zones.zones.last?.upperBound ?? HeartRateZoneConfiguration.observedMax(in: runs.filter { $0.activity.isRun })
        let rideObserved = HeartRateZoneConfiguration.observedMax(in: rides)
        if settings.usesOwnRideZones {
            maxHeartRate[.cycling] = settings.cyclingZones.zones.last?.upperBound ?? rideObserved
        } else if maxHeartRate[.running] == nil {
            // Quien solo pedalea: la máxima registrada en sus salidas.
            maxHeartRate[.cycling] = rideObserved
        }
        var sex = ReferenceProfileStore.shared.sex
        if sex == nil {
            sex = await provider.userCharacteristics().sex
        }
        return HeartRateLoadInputs(restingHeartRate: restingHeartRate, maxHeartRate: maxHeartRate, sex: sex)
    }
}

/// "Carga de entrenamiento": últimos 7 días frente a tu media, 12 semanas por
/// deporte y forma física, fatiga y frescura (modelo de Banister).
struct TrainingLoadCard: View {
    /// En CYKEL se puede elegir la carga con potencia (TSS) si hay datos.
    var allowsPower = false
    var powerFTP: Double?
    @Environment(AppModel.self) private var model
    @State private var store = TrainingLoadStore.shared
    @State private var settings = RunSettingsStore.shared
    @AppStorage("halsyn.load.metric") private var storedMetric: LoadMetric = .heartRate

    private var metric: LoadMetric { allowsPower && powerFTP != nil ? storedMetric : .heartRate }

    private var key: String {
        let current = settings.settings
        let sex = ReferenceProfileStore.shared.sex?.rawValue ?? "-"
        // El FTP solo cambia la carga con potencia: así SPRING y CYKEL comparten la de pulso.
        let ftp = metric == .power ? powerFTP ?? 0 : 0
        return "\(model.reloadKey)|\(metric.rawValue)|\(ftp)|\(current.zones.hashValue)|\(current.rideZones?.hashValue ?? 0)|\(sex)"
    }

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Carga de entrenamiento", eyebrow: HalsynLexicon.form.rawValue)
                if allowsPower && powerFTP != nil {
                    Picker("Medir con", selection: $storedMetric) {
                        ForEach(LoadMetric.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let summary = store.summary(metric, key: key) {
                    TrainingLoadContent(summary: summary, inputs: metric == .heartRate ? store.inputs : nil)
                } else {
                    HalsynLoadingState()
                }
            }
        }
        .task(id: key) {
            await store.load(metric, provider: model.provider, settings: settings.settings, ftp: powerFTP, key: key)
        }
    }
}

private enum LoadSport: Int, CaseIterable, Identifiable {
    case running, walking, cycling

    var id: Int { rawValue }

    var sport: WorkoutSport {
        switch self {
        case .running: .running
        case .walking: .walking
        case .cycling: .cycling
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .running: "Correr"
        case .walking: "Caminar"
        case .cycling: "Bici"
        }
    }

    var color: Color {
        switch self {
        case .running: .halsynAccent
        case .walking: .halsynSecondaryText
        case .cycling: .halsynHighlight
        }
    }
}

private struct TrainingLoadContent: View {
    let summary: TrainingLoadSummary
    let inputs: HeartRateLoadInputs?

    private let columns = [GridItem(.flexible(), spacing: HalsynSpacing.s), GridItem(.flexible(), spacing: HalsynSpacing.s), GridItem(.flexible(), spacing: HalsynSpacing.s)]

    var body: some View {
        if summary.historyDays == 0 {
            Text(summary.metric == .power
                 ? LocalizedStringKey("Todavía no hay salidas con potencia y FTP para calcular la carga.")
                 : LocalizedStringKey("Todavía no hay entrenamientos con frecuencia cardíaca para calcular la carga. Hacen falta tu FC en reposo (de Salud) y tu FC máxima (en tus zonas o la más alta registrada)."))
                .font(.halsynCaption)
                .foregroundStyle(.halsynPrimaryText)
        } else {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(alignment: .top) {
                    HalsynMetric(title: "Últimos 7 días", value: HalsynFormat.integer(summary.last7Days), unit: "")
                    Spacer()
                    HalsynMetric(title: "Media semanal antes", value: summary.previousWeeklyAverage.map { HalsynFormat.integer($0) }, unit: "", alignment: .trailing)
                }
                if let ratio = summary.ratio {
                    Text(comparison(ratio))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynPrimaryText)
                }
                weeksChart
                legend
                Divider().overlay(Color.halsynHairline)
                if let today = summary.today {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: HalsynSpacing.s) {
                        HalsynMetric(title: "Forma física", value: HalsynFormat.integer(today.fitness), unit: "")
                        HalsynMetric(title: "Fatiga", value: HalsynFormat.integer(today.fatigue), unit: "")
                        HalsynMetric(title: "Frescura al empezar hoy", value: signed(today.form), unit: "")
                    }
                    if !summary.isBuildingUp {
                        Text(formText(today.form))
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    fitnessChart
                }
                if summary.isBuildingUp {
                    HalsynStatusIndicator(.caution, text: "La forma física necesita unos 3 meses de datos: por ahora sale más baja de lo real y la frescura, más negativa.")
                }
                footnotes
            }
        }
    }

    // MARK: Gráficos

    private struct WeekBar: Identifiable {
        let id: String
        let week: Date
        let sport: LoadSport
        let value: Double
    }

    private var weekBars: [WeekBar] {
        summary.weeks.flatMap { week in
            LoadSport.allCases.compactMap { sport -> WeekBar? in
                guard let value = week.bySport[sport.sport], value > 0 else { return nil }
                return WeekBar(id: "\(week.start.timeIntervalSince1970)-\(sport.rawValue)", week: week.start, sport: sport, value: value)
            }
        }
    }

    private var weeksChart: some View {
        Chart(weekBars) { bar in
            BarMark(x: .value("Semana", bar.week, unit: .weekOfYear), y: .value("Carga", bar.value))
                .foregroundStyle(bar.sport.color)
                .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 130)
        .accessibilityLabel(Text("Carga por semana, últimas 12 semanas"))
    }

    private var legend: some View {
        HStack(spacing: HalsynSpacing.m) {
            ForEach(LoadSport.allCases.filter { sport in summary.weeks.contains { ($0.bySport[sport.sport] ?? 0) > 0 } }) { sport in
                HStack(spacing: 4) {
                    Circle().fill(sport.color).frame(width: 8, height: 8)
                    Text(sport.title)
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
            Spacer()
            Text("Últimas 12 semanas")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    private struct ModelLine: Identifiable {
        let id: String
        let day: Date
        let value: Double
        let series: Int
    }

    private var modelLines: [ModelLine] {
        summary.points.flatMap { point in
            [
                ModelLine(id: "f\(point.day.timeIntervalSince1970)", day: point.day, value: point.fitness, series: 0),
                ModelLine(id: "a\(point.day.timeIntervalSince1970)", day: point.day, value: point.fatigue, series: 1),
            ]
        }
    }

    private var fitnessChart: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            Chart(modelLines) { line in
                LineMark(x: .value("Día", line.day), y: .value("Valor", line.value), series: .value("Serie", line.series))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(line.series == 0 ? Color.halsynAccent : Color.halsynCaution)
            }
            .frame(height: 110)
            .accessibilityLabel(Text("Forma física y fatiga, últimos 90 días"))
            HStack(spacing: HalsynSpacing.m) {
                legendItem("Forma física (42 días)", color: .halsynAccent)
                legendItem("Fatiga (7 días)", color: .halsynCaution)
            }
        }
    }

    private func legendItem(_ title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 12, height: 3)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    // MARK: Textos

    private func comparison(_ ratio: Double) -> LocalizedStringKey {
        let count = Int((abs(ratio - 1) * 100).rounded())
        if ratio >= 1.1 {
            return "Un \(count) por ciento más que tu media semanal de las 4 semanas anteriores."
        } else if ratio <= 0.9 {
            return "Un \(count) por ciento menos que tu media semanal de las 4 semanas anteriores."
        }
        return "Parecida a tu media semanal de las 4 semanas anteriores."
    }

    /// Frescura (forma − fatiga al terminar ayer), con el mismo redondeo que se muestra.
    private func formText(_ form: Double) -> LocalizedStringKey {
        let rounded = Int(form.rounded())
        if rounded > 0 {
            return "Frescura positiva: al terminar ayer tu fatiga (media de 7 días) estaba por debajo de tu forma física (media de 42 días)."
        } else if rounded < 0 {
            return "Frescura negativa: al terminar ayer tu fatiga (media de 7 días) superaba tu forma física (media de 42 días)."
        }
        return "Frescura neutra: al terminar ayer tu fatiga y tu forma física estaban igualadas."
    }

    private func signed(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    @ViewBuilder
    private var footnotes: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            if summary.skipped > 0 {
                let skipped = summary.skipped
                Text(summary.metric == .power
                     ? LocalizedStringKey("\(skipped) salidas sin potencia no suman en esta vista.")
                     : LocalizedStringKey("\(skipped) entrenamientos sin FC media o sin FC máxima para su deporte no suman."))
            }
            if let inputs {
                Text(inputsText(inputs))
            }
            Text(summary.metric == .power
                 ? LocalizedStringKey("Carga de cada salida con potencia: TSS (una hora a tu FTP = 100). La forma física es la media exponencial de 42 días; la fatiga, la de 7; la frescura, su diferencia al terminar ayer (cómo llegas a hoy), como en el gráfico de rendimiento de Coggan.")
                 : LocalizedStringKey("Carga de cada entrenamiento: TRIMP de Banister, con la duración y la FC media frente a tu FC en reposo y máxima. La forma física es la media exponencial de 42 días; la fatiga, la de 7; la frescura, su diferencia al terminar ayer (cómo llegas a hoy). Son tendencias para entrenar, no una medida médica."))
            if let ratio = summary.ratio, ratio >= 1.5 {
                Text("Subir mucho la carga de una semana a otra se asoció con más lesiones en algunos estudios, aunque ese cociente está discutido: tómalo como aviso, no como regla.")
            }
            ReferenceLinks(references: summary.metric == .power
                           ? [ScienceReferences.powerMeterTraining, ScienceReferences.performanceManager, ScienceReferences.fitnessFatigueModel, ScienceReferences.trainingLoad, ScienceReferences.workloadRatioPitfalls]
                           : [ScienceReferences.banisterTRIMP, ScienceReferences.trimpValidation, ScienceReferences.performanceManager, ScienceReferences.fitnessFatigueModel, ScienceReferences.trainingLoad, ScienceReferences.workloadRatioPitfalls])
        }
        .font(.caption2)
        .foregroundStyle(.halsynSecondaryText)
    }

    private func inputsText(_ inputs: HeartRateLoadInputs) -> LocalizedStringKey {
        let resting = inputs.restingHeartRate.map { HalsynFormat.integer($0) } ?? "—"
        let running = inputs.max(for: .running).map { HalsynFormat.integer($0) } ?? "—"
        let cycling = inputs.max(for: .cycling).map { HalsynFormat.integer($0) } ?? "—"
        if inputs.sex == nil {
            return "Con FC en reposo \(resting), FC máx. \(running) corriendo y \(cycling) en bici. Sin sexo en tu perfil, se usa la media de las curvas de hombres y mujeres."
        }
        return "Con FC en reposo \(resting), FC máx. \(running) corriendo y \(cycling) en bici."
    }
}
