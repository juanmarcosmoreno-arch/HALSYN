import HalsynCore
import HalsynDesign
import Observation
import SwiftUI

/// Tests y carreras a tope registrados. Solo en este iPhone.
@MainActor
@Observable
final class FitnessStore {
    static let shared = FitnessStore()
    static let key = "halsyn.performanceResults"

    private(set) var results: [PerformanceResult]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        results = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([PerformanceResult].self, from: $0) } ?? []
    }

    func add(_ result: PerformanceResult) {
        results.removeAll { $0.id == result.id || ($0.workoutID != nil && $0.workoutID == result.workoutID) }
        results.append(result)
        results.sort { $0.date > $1.date }
        persist()
    }

    func remove(_ id: UUID) {
        results.removeAll { $0.id == id }
        persist()
    }

    func estimate(runs: [WorkoutSummary], today: Date = .now) -> FitnessEstimate? {
        FitnessEstimator.estimate(results: results, runs: runs, today: today, calendar: .current)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(results) { defaults.set(data, forKey: Self.key) }
    }
}

// MARK: - Textos

enum RaceGoalText {
    static func verdictTitle(_ verdict: GoalAssessment.Verdict) -> String {
        switch verdict {
        case .alreadyThere: String(localized: "Tu forma de hoy ya da ese tiempo")
        case .realistic: String(localized: "Objetivo realista")
        case .ambitious: String(localized: "Objetivo ambicioso")
        case .unlikely: String(localized: "Objetivo poco probable")
        }
    }

    static func verdictDetail(_ assessment: GoalAssessment) -> LocalizedStringKey {
        let reachable = HalsynFormat.duration(assessment.reachableTime)
        switch assessment.verdict {
        case .alreadyThere?: return "Con tu forma actual ya podrías correrlo. Puedes mantenerlo o proponerte algo más."
        case .realistic?: return "Pide una mejora dentro de lo habitual para las semanas que quedan."
        case .ambitious?: return "Pide mejorar más rápido de lo habitual. Es posible, pero no lo des por hecho."
        case .unlikely?: return "Pide más del doble de la mejora habitual. Un objetivo cerca de \(reachable) es más alcanzable."
        case nil: return "Sin tiempo objetivo: el plan te prepara para la distancia con tu forma actual."
        }
    }

    static func verdictStatus(_ verdict: GoalAssessment.Verdict) -> HalsynStatusIndicator.Level {
        switch verdict {
        case .alreadyThere, .realistic: .positive
        case .ambitious: .neutral
        case .unlikely: .caution
        }
    }

    static func warning(_ warning: GoalAssessment.Warning, weekly: Double, unit: UnitSystem) -> LocalizedStringKey {
        switch warning {
        case .shortPreparation(let weeks):
            return "Para esta distancia se suelen recomendar al menos \(weeks) semanas de preparación."
        case .lowVolume(let minimum):
            let now = SessionText.distance(weekly, unit: unit)
            let needed = SessionText.distance(minimum, unit: unit)
            return "Ahora corres unos \(now) por semana; para preparar esta distancia conviene partir de unos \(needed)."
        case .estimateFromTraining:
            return "Tu forma sale de tus entrenamientos y probablemente se queda corta: el test de la primera semana la afina."
        case .staleEstimate:
            return "Tu último test o carrera tiene más de 6 semanas: conviene repetirlo."
        }
    }

    static func source(_ estimate: FitnessEstimate, unit: UnitSystem) -> String {
        switch estimate.source {
        case .result(let result):
            let distance = SessionText.distance(result.distance, unit: unit)
            let date = result.date.formatted(.dateTime.day().month(.abbreviated))
            return result.kind == .test
                ? String(localized: "Test de \(distance) del \(date)")
                : String(localized: "Carrera de \(distance) del \(date)")
        case .training:
            return String(localized: "Mejor esfuerzo de tus entrenamientos de las últimas 6 semanas")
        }
    }

    static func progress(_ progress: PlanProgress, unit: UnitSystem) -> LocalizedStringKey {
        let done = SessionText.distance(progress.actualDistance, unit: unit)
        let planned = SessionText.distance(progress.plannedDistance, unit: unit)
        switch progress.status {
        case .notStarted: return "Aún no hay una semana completa del plan para comparar."
        case .onTrack: return "Vas bien: hiciste \(done) de \(planned) planeados en las últimas semanas."
        case .slightlyBehind: return "Algo por debajo: hiciste \(done) de \(planned) planeados. El plan se reajusta solo cada semana."
        case .behind: return "Por debajo del plan: hiciste \(done) de \(planned). Bajamos el volumen para retomar sin forzar."
        case .abovePlan: return "Hiciste \(done) de \(planned) planeados, más de lo previsto. No subas más deprisa: el descanso también entrena."
        }
    }

    static func progressStatus(_ status: PlanProgress.Status) -> HalsynStatusIndicator.Level {
        switch status {
        case .onTrack: .positive
        case .notStarted, .slightlyBehind: .neutral
        case .behind, .abovePlan: .caution
        }
    }

    static func adjustment(_ adjustment: PlanAdjustment, unit: UnitSystem) -> LocalizedStringKey {
        let before = SessionText.distance(adjustment.previousVolume, unit: unit)
        let after = SessionText.distance(adjustment.newVolume, unit: unit)
        switch adjustment.reason {
        case .behind: return "Plan reajustado: la próxima semana son \(after) (antes \(before)), porque la anterior hiciste menos. Lo que no hiciste no se recupera."
        case .abovePlan: return "Hiciste más de lo planeado: mantenemos la progresión para no cargar de golpe."
        case .onTrack: return "Plan revisado: vas según lo previsto y la próxima semana sigue igual."
        case .fitnessUpdated: return "Tu forma cambió con el último resultado: ritmos y semanas actualizados."
        }
    }

    static func vdot(_ value: Double) -> String { HalsynFormat.decimal(value, fractionDigits: 1) }
}

// MARK: - Duración

/// Horas, minutos y segundos con ruedas.
struct DurationPicker: View {
    @Binding var seconds: TimeInterval
    var maximumHours = 6

    var body: some View {
        let total = Int(seconds.rounded())
        HStack(spacing: 0) {
            wheel(value: total / 3600, range: 0...maximumHours, unit: "h") { set(hours: $0) }
            wheel(value: (total % 3600) / 60, range: 0...59, unit: "min") { set(minutes: $0) }
            wheel(value: total % 60, range: 0...59, unit: "s") { set(seconds: $0) }
        }
        .frame(height: 130)
    }

    private func wheel(value: Int, range: ClosedRange<Int>, unit: String, set: @escaping (Int) -> Void) -> some View {
        Picker(selection: Binding(get: { value }, set: set)) {
            ForEach(Array(range), id: \.self) { number in
                Text(verbatim: "\(number) \(unit)").tag(number)
            }
        } label: {
            Text(verbatim: unit)
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func set(hours: Int? = nil, minutes: Int? = nil, seconds newSeconds: Int? = nil) {
        let total = Int(seconds.rounded())
        let h = hours ?? total / 3600
        let m = minutes ?? (total % 3600) / 60
        let s = newSeconds ?? total % 60
        seconds = TimeInterval(h * 3600 + m * 60 + s)
    }
}

// MARK: - Registrar un resultado

/// Test o carrera a tope: distancia, tiempo y fecha. Muestra el VDOT y sus
/// equivalencias antes de guardar.
struct ResultEntryView: View {
    var prefill: PerformanceResult?
    var onSave: (PerformanceResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var kind: PerformanceResult.Kind = .test
    @State private var preset: Double = 5000
    @State private var otherKilometers: Double?
    @State private var time: TimeInterval = 25 * 60
    @State private var date = Date.now
    @State private var loaded = false

    static let presets: [Double] = [3000, 5000, 10_000, RaceDistance.half.rawValue, RaceDistance.marathon.rawValue, 0]

    private var distance: Double? {
        preset > 0 ? preset : otherKilometers.map { $0 * 1000 }
    }

    private var result: PerformanceResult? {
        guard let distance, distance > 0 else { return nil }
        let candidate = PerformanceResult(id: prefill?.id ?? UUID(), date: date, distance: distance, time: time, kind: kind, workoutID: prefill?.workoutID)
        return candidate.vdot == nil ? nil : candidate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $kind) {
                        Text("Test").tag(PerformanceResult.Kind.test)
                        Text("Carrera").tag(PerformanceResult.Kind.race)
                    }
                    .pickerStyle(.segmented)
                    Picker("Distancia", selection: $preset) {
                        ForEach(Self.presets, id: \.self) { meters in
                            if meters == 0 {
                                Text("Otra").tag(meters)
                            } else {
                                Text(verbatim: SessionText.distance(meters, unit: unitSystem)).tag(meters)
                            }
                        }
                    }
                    if preset == 0 {
                        LabeledContent("Kilómetros") {
                            TextField("Kilómetros", value: $otherKilometers, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    DatePicker("Fecha", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("Solo esfuerzos a tope: un test o una carrera. Un rodaje no sirve para medir tu forma.")
                }

                Section("Tiempo") {
                    DurationPicker(seconds: $time)
                }

                Section {
                    if let result, let vdot = result.vdot {
                        LabeledContent("Tu forma (VDOT)", value: RaceGoalText.vdot(vdot))
                        ForEach([RaceDistance.fiveK, .tenK, .half, .marathon]) { target in
                            LabeledContent {
                                Text(verbatim: HalsynFormat.duration(VDOT.raceTime(vdot: vdot, distance: target.rawValue)))
                                    .monospacedDigit()
                            } label: {
                                Text(LocalizedStringKey(target.title))
                            }
                        }
                    } else {
                        Text("Revisa la distancia y el tiempo: tienen que ser de un esfuerzo de entre unos 4 minutos y 5 horas.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Equivale a")
                } footer: {
                    Text("Tablas de Daniels y Gilbert: tiempos equivalentes si entrenas para cada distancia.")
                }
            }
            .navigationTitle(Text("Registrar resultado"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if let result {
                            onSave(result)
                            dismiss()
                        }
                    }
                    .disabled(result == nil)
                }
            }
            .onAppear {
                guard !loaded, let prefill else { return }
                loaded = true
                kind = prefill.kind
                date = prefill.date
                time = prefill.time.rounded()
                if Self.presets.contains(prefill.distance) {
                    preset = prefill.distance
                } else {
                    preset = 0
                    otherKilometers = (prefill.distance / 10).rounded() / 100
                }
            }
        }
    }
}

// MARK: - Objetivo y progreso

/// "Tu objetivo": viabilidad, progreso, forma actual y resultados.
struct GoalStatusCard: View {
    let plan: TrainingPlan
    let runs: [WorkoutSummary]
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var entering: PerformanceResult?
    @State private var enteringNew = false
    private var fitness: FitnessStore { .shared }

    var body: some View {
        let estimate = fitness.estimate(runs: runs)
        let progress = PlanProgress.evaluate(plan: plan, runs: runs, estimate: estimate, today: .now, calendar: .current)
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Tu objetivo", eyebrow: HalsynModule.mal.brandName)
                HStack(alignment: .firstTextBaseline) {
                    Text(LocalizedStringKey(plan.goal.distance.title))
                        .font(.halsynHeadline)
                    Spacer()
                    if let goal = plan.goal.goalTime {
                        Text(verbatim: HalsynFormat.duration(goal))
                            .font(.halsynMetricValue)
                    }
                }
                if let estimate {
                    let assessment = GoalCoach.assess(goalTime: plan.goal.goalTime, distance: plan.goal.distance, raceDate: plan.goal.raceDate, estimate: estimate, weeklyDistance: plan.startingWeeklyDistance, today: .now, calendar: .current)
                    if let verdict = assessment.verdict {
                        HalsynStatusIndicator(RaceGoalText.verdictStatus(verdict), text: RaceGoalText.verdictTitle(verdict))
                    }
                    Text(RaceGoalText.verdictDetail(assessment))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    timeRow("Con tu forma de hoy", assessment.predictedTime)
                    if let projected = progress.projectedTime {
                        timeRow("Previsto el día de la carrera", projected)
                    }
                }

                Divider().overlay(Color.halsynHairline)
                HalsynStatusIndicator(RaceGoalText.progressStatus(progress.status), text: progressTitle(progress.status))
                Text(RaceGoalText.progress(progress, unit: unitSystem))
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let adjustment = plan.lastAdjustment {
                    Label {
                        Text(RaceGoalText.adjustment(adjustment, unit: unitSystem))
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Color.halsynHairline)
                if let estimate {
                    LabeledContent {
                        Text(verbatim: RaceGoalText.vdot(estimate.vdot)).monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Tu forma (VDOT)")
                            Text(verbatim: RaceGoalText.source(estimate, unit: unitSystem))
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                    .font(.halsynCaption)
                    if estimate.needsTest(today: .now, calendar: .current) {
                        Label("Conviene un test: está en tu plan, o regístralo si ya lo hiciste.", systemImage: "stopwatch")
                            .font(.caption2)
                            .foregroundStyle(.halsynCaution)
                    }
                }
                ForEach(fitness.results.prefix(4)) { result in
                    resultRow(result)
                }
                Button {
                    enteringNew = true
                } label: {
                    Label("Registrar un test o una carrera", systemImage: "plus.circle")
                        .font(.halsynCaption.weight(.semibold))
                }
                .buttonStyle(.borderless)

                Text("El VDOT es la forma estimada a partir de un esfuerzo a tope (Daniels y Gilbert). La mejora habitual sigue la pauta de Daniels de subir como mucho 1 punto cada 4 a 6 semanas; la tuya puede ser distinta.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ReferenceLinks(references: [ScienceReferences.danielsVDOT, ScienceReferences.gradedTraining, ScienceReferences.weeklyProgression, ScienceReferences.taper])
            }
        }
        .sheet(isPresented: $enteringNew) {
            ResultEntryView { save($0) }
        }
        .sheet(item: $entering) { prefill in
            ResultEntryView(prefill: prefill) { save($0) }
        }
    }

    private func save(_ result: PerformanceResult) {
        FitnessStore.shared.add(result)
        TrainingPlanStore.shared.applyLatestFitness(runs: runs)
    }

    private func progressTitle(_ status: PlanProgress.Status) -> String {
        switch status {
        case .notStarted: String(localized: "Empezando")
        case .onTrack: String(localized: "Vas bien")
        case .slightlyBehind: String(localized: "Algo por debajo")
        case .behind: String(localized: "Por debajo del plan")
        case .abovePlan: String(localized: "Por encima del plan")
        }
    }

    private func timeRow(_ title: LocalizedStringKey, _ time: TimeInterval) -> some View {
        LabeledContent {
            Text(verbatim: HalsynFormat.duration(time)).monospacedDigit()
        } label: {
            Text(title)
        }
        .font(.halsynCaption)
    }

    private func resultRow(_ result: PerformanceResult) -> some View {
        HStack {
            Image(systemName: result.kind == .test ? "stopwatch" : "flag.checkered")
                .foregroundStyle(.halsynAccentText)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: SessionText.distance(result.distance, unit: unitSystem) + " · " + HalsynFormat.duration(result.time))
                    .font(.halsynCaption.monospacedDigit())
                Text(result.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
            Spacer()
            if let vdot = result.vdot {
                Text(verbatim: RaceGoalText.vdot(vdot))
                    .font(.halsynCaption.monospacedDigit())
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { entering = result }
        .contextMenu {
            Button("Borrar", role: .destructive) {
                FitnessStore.shared.remove(result.id)
                TrainingPlanStore.shared.applyLatestFitness(runs: runs)
            }
        }
    }
}

extension PerformanceResult {
    /// Resultado propuesto a partir de un entrenamiento detectado como test.
    init(testWorkout workout: WorkoutSummary) {
        self.init(date: workout.start, distance: workout.distanceMeters ?? 0, time: workout.duration, kind: .test, workoutID: workout.id)
    }
}
