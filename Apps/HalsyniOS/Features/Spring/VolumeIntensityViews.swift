import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

/// Datos para clasificar la intensidad de tus entrenamientos.
@MainActor
enum IntensityContext {
    /// Últimas carreras vistas (para la FC máxima de referencia al clasificar una sola).
    static var history: [WorkoutSummary] = []
    /// FC máxima de referencia usada en la última clasificación.
    static var lastReference: Double?

    /// ¿Sirve para el VDOT? (mismos criterios que el modelo de rendimiento).
    static func eligibility(_ workout: WorkoutSummary) -> VDOTEligibility {
        let marked = FitnessStore.shared.results.first { $0.workoutID == workout.id }?.kind
        let quality = DataQuality.assess([workout])[workout.id]
        let reference = lastReference ?? FitnessStore.shared.maxHeartRate(for: history).value
        return EffortClassifier.eligibility(workout, maxHeartRate: reference, thresholdHeartRate: RunSettingsStore.shared.settings.zones.validThreshold, plannedKind: FitnessStore.shared.plannedKinds[Calendar.current.startOfDay(for: workout.start)], marked: marked, rejected: FitnessStore.shared.rejected.contains(workout.id), quality: quality)
    }

    /// Clasificación de cada entrenamiento (con muestras de pulso si las hay).
    static func intensities(_ workouts: [WorkoutSummary], samples: [UUID: [HeartRatePoint]] = [:]) -> [UUID: WorkoutIntensity] {
        let quality = DataQuality.assess(workouts)
        var runs = workouts.filter(\.activity.isRun)
        if runs.count >= 5 { history = runs } else { runs = history.isEmpty ? runs : history }
        // Configurada, salvo que quede por debajo de lo registrado (sin duplicados).
        let maxHeartRate = FitnessStore.shared.maxHeartRate(for: runs).value
        let zones = RunSettingsStore.shared.settings.zones
        let threshold = zones.validThreshold
        // Zonas por umbral: la intensidad se mide frente a tu FC de umbral (Friel).
        let lactateThreshold = zones.method == .lactateThreshold ? threshold : nil
        let thresholdPace = FitnessStore.shared.performance(runs: runs).map {
            TrainingPaces.from(vdot: $0.currentVDOT, target: .tenK).tempo.center.secondsPerKilometer
        }
        var marks: [UUID: PerformanceResult.Kind] = [:]
        for result in FitnessStore.shared.results {
            if let id = result.workoutID { marks[id] = result.kind }
        }
        var planned: [Date: SessionKind] = [:]
        for session in TrainingPlanStore.shared.plan?.weeks.flatMap(\.sessions) ?? [] {
            planned[Calendar.current.startOfDay(for: session.date)] = session.kind
        }
        lastReference = maxHeartRate
        var result: [UUID: WorkoutIntensity] = [:]
        for workout in workouts {
            result[workout.id] = IntensityClassifier.classify(
                workout,
                maxHeartRate: maxHeartRate,
                thresholdHeartRate: threshold,
                thresholdPace: workout.activity.isRun ? thresholdPace : nil,
                samples: samples[workout.id],
                marked: marks[workout.id],
                plannedKind: workout.activity.isRun ? planned[Calendar.current.startOfDay(for: workout.start)] : nil,
                quality: quality[workout.id],
                lactateThreshold: workout.activity.isRun ? lactateThreshold : nil
            )
        }
        return result
    }
}

enum IntensityText {
    static func title(_ kind: IntensityClass) -> String {
        String(localized: String.LocalizationValue(kind.title))
    }

    static func basis(_ intensity: WorkoutIntensity) -> String {
        switch intensity.basis {
        case .marked: String(localized: "lo marcaste tú")
        case .heartRate: String(localized: "por tu pulso")
        case .pace: String(localized: "aproximado, por el ritmo (sin pulso)")
        case .perceivedEffort: String(localized: "aproximado, por el esfuerzo percibido")
        case .none: String(localized: "sin pulso ni ritmo para clasificarlo")
        }
    }

    static func eligibility(_ eligibility: VDOTEligibility) -> String {
        switch eligibility {
        case .confirmed: return String(localized: "Para el VDOT: confirmado por ti (test o competición).")
        case .candidate: return String(localized: "Para el VDOT: candidato a esfuerzo máximo, no confirmado. Solo puede subir tu estimación.")
        case let .notEligible(reason):
            let text: String
            switch reason {
            case .noHeartRate: text = String(localized: "sin pulso fiable")
            case .lowHeartRate: text = String(localized: "pulso medio por debajo del 90 % de tu máxima")
            case .belowThreshold: text = String(localized: "pulso medio por debajo de tu FC de umbral")
            case .duration: text = String(localized: "duración fuera de 8–75 min")
            case .distance: text = String(localized: "menos de 3 km")
            case .treadmill: text = String(localized: "en cinta (distancia estimada)")
            case .hilly: text = String(localized: "mucho desnivel (más de 10 m por km)")
            case .plannedEasy: text = String(localized: "había un rodaje suave o largo planificado")
            case .plannedWorkout: text = String(localized: "era una sesión de umbral o de series del plan; si fue a tope, confírmala como test")
            case .rejected: text = String(localized: "lo descartaste tú")
            case .quality: text = String(localized: "datos dudosos (distancia o ritmo)")
            }
            return String(localized: "Para el VDOT: no se usa (\(text)).")
        }
    }
}

/// Volumen semanal e intensidad: 12 semanas, tendencias, descanso y aumentos
/// bruscos respecto de tu propio historial.
struct VolumeIntensityCard: View {
    let runs: [WorkoutSummary]
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var analysis: TrainingVolumeAnalysis?

    private struct Bar: Identifiable {
        let id: String
        let week: Date
        let bucket: String
        let minutes: Double
    }

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Volumen e intensidad", eyebrow: HalsynModule.spring.brandName)
                if let analysis {
                    content(analysis)
                } else {
                    HalsynLoadingState()
                }
            }
        }
        .task(id: runs.count) { await load() }
    }

    @ViewBuilder
    private func content(_ analysis: TrainingVolumeAnalysis) -> some View {
        let bars = analysis.weeks.flatMap { week in
            IntensityBucket.allCases.map { bucket in
                Bar(id: "\(week.start.timeIntervalSince1970)-\(bucket.rawValue)", week: week.start, bucket: String(localized: String.LocalizationValue(bucket.title)), minutes: week.minutesByBucket[bucket] ?? 0)
            }
        }
        Chart(bars) { bar in
            BarMark(x: .value("Semana", bar.week, unit: .weekOfYear), y: .value("Minutos", bar.minutes))
                .foregroundStyle(by: .value("Intensidad", bar.bucket))
        }
        .chartForegroundStyleScale([
            String(localized: "Suave"): Color.halsynChart.opacity(0.45),
            String(localized: "Moderado"): Color.halsynChart.opacity(0.75),
            String(localized: "Intenso"): Color.halsynHighlight,
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 170)
        .accessibilityLabel(Text("Minutos de carrera por semana según la intensidad"))

        VStack(spacing: 4) {
            row(String(localized: "Esta semana"), distance(analysis.weeks.last?.runDistance))
            row(String(localized: "Media de 4 semanas"), distance(analysis.average4))
            row(String(localized: "Media de 8 semanas"), distance(analysis.average8))
            row(String(localized: "Media de 12 semanas"), distance(analysis.average12))
            if let trend = analysis.trendPerWeek {
                row(String(localized: "Tendencia (8 semanas)"), (trend >= 0 ? "+" : "−") + SessionText.distance(abs(trend), unit: unitSystem) + " / " + String(localized: "semana"))
            }
            row(String(localized: "Días sin entrenar (14 días)"), String(analysis.restDaysLast14))
            row(String(localized: "Racha más larga entrenando (28 días)"), String(analysis.longestStreakLast28))
            row(String(localized: "Días intensos seguidos (14 días)"), String(analysis.consecutiveHardDays))
        }
        if !analysis.intensityShare.isEmpty {
            let low = percent(analysis.intensityShare[.low]), moderate = percent(analysis.intensityShare[.moderate]), high = percent(analysis.intensityShare[.high])
            Text("Últimas 4 semanas: \(low) suave · \(moderate) moderado · \(high) intenso (por tiempo de carrera).")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
        if analysis.isUnusualIncrease, let change = analysis.lastWeekChange {
            let changeText = String(Int((change * 100).rounded()))
            Label("La semana pasada corriste un \(changeText) % más que tu media de las 4 anteriores, más de lo que sueles variar. No predice una lesión, pero conviene subir de a poco.", systemImage: "chart.line.uptrend.xyaxis")
                .font(.caption2)
                .foregroundStyle(.halsynCaution)
                .fixedSize(horizontal: false, vertical: true)
        }
        if analysis.consecutiveHardDays >= 3 {
            Label("Encadenaste varios días intensos seguidos: un día suave entre medio ayuda a asimilarlos.", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.halsynCaution)
                .fixedSize(horizontal: false, vertical: true)
        }
        ExpandableText("Cada carrera se clasifica en recuperación, suave, moderado, tempo, series o a tope con su pulso medio frente a tu FC máxima (y las subidas y bajadas del pulso, para las series). Sin pulso se usa el ritmo frente a tu ritmo de umbral, y se marca como aproximado. Ir rápido no basta para contar como «a tope»: hace falta el pulso. Los días sin entrenar incluyen todas las actividades (bici y caminatas también). El aviso de aumento compara con tu propio historial, no con un umbral universal.")
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.halsynCaption)
    }

    private func distance(_ meters: Double?) -> String {
        meters.map { SessionText.distance($0, unit: unitSystem) } ?? "—"
    }

    private func percent(_ value: Double?) -> String {
        "\(Int(((value ?? 0) * 100).rounded())) %"
    }

    private func load() async {
        let calendar = Calendar.current
        let rides = await model.provider.recentRides(limit: 200)
        let start = calendar.date(byAdding: .day, value: -7 * TrainingVolumeAnalysis.weekCount, to: .now) ?? .now
        let workouts = WorkoutQualityStore.shared.clean((runs + rides).filter { $0.start >= start })
        // Muestras de pulso de las carreras de las últimas 4 semanas (para detectar series).
        let samplesStart = calendar.date(byAdding: .day, value: -28, to: .now) ?? .now
        var samples: [UUID: [HeartRatePoint]] = [:]
        for run in workouts.filter({ $0.activity.isRun && $0.start >= samplesStart && $0.averageHeartRate != nil }).prefix(40) {
            guard !Task.isCancelled else { return }
            let points = await model.provider.workoutDetail(for: run).heartRate
            if !points.isEmpty { samples[run.id] = points }
        }
        let intensities = IntensityContext.intensities(workouts, samples: samples)
        analysis = TrainingVolumeAnalysis.compute(workouts: workouts, intensities: intensities, today: .now, calendar: calendar)
    }
}
