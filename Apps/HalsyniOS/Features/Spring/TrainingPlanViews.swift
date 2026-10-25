import Charts
import HalsynCore
import HalsynDesign
import Observation
import SwiftUI

/// Plan de entrenamiento guardado en este iPhone.
@MainActor
@Observable
final class TrainingPlanStore {
    static let shared = TrainingPlanStore()
    static let key = "halsyn.trainingPlan"
    /// Id del plan de intervalos que se envía al reloj con la sesión del día.
    static let watchPlanID = "halsyn-plan-today"

    private(set) var plan: TrainingPlan?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        plan = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(TrainingPlan.self, from: $0) }
    }

    func save(_ plan: TrainingPlan?) {
        self.plan = plan
        if let plan, let data = try? JSONEncoder().encode(plan) {
            defaults.set(data, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
            RunSettingsStore.shared.update { settings in settings.intervalPlans.removeAll { $0.id == Self.watchPlanID } }
        }
    }

    /// Reajuste semanal automático (una vez por semana).
    func replanIfNeeded(runs: [WorkoutSummary]) {
        // Con datos de demostración no se reajusta: el plan es del usuario real.
        guard let plan, !runs.contains(where: \.origin.isDemo),
              TrainingPlanGenerator.needsWeeklyReplan(plan, today: .now, calendar: .current) else { return }
        save(TrainingPlanGenerator.replan(plan, runs: runs, estimate: FitnessStore.shared.estimate(runs: runs), today: .now, calendar: .current))
    }

    /// Tras registrar o borrar un resultado: ritmos y semanas con la forma nueva.
    func applyLatestFitness(runs: [WorkoutSummary]) {
        guard let plan, !runs.contains(where: \.origin.isDemo) else { return }
        save(TrainingPlanGenerator.replan(plan, runs: runs, estimate: FitnessStore.shared.estimate(runs: runs), updatingFitness: true, today: .now, calendar: .current))
    }

    /// Pone la sesión en el reloj (SPRING › Intervalos), sustituyendo la anterior del plan.
    func sendToWatch(_ session: PlannedSession) -> Bool {
        let name = String(localized: String.LocalizationValue(session.kind.title))
        guard let watchPlan = PlanAdaptation.intervalPlan(for: session, id: Self.watchPlanID, name: name) else { return false }
        RunSettingsStore.shared.update { settings in
            settings.intervalPlans.removeAll { $0.id == Self.watchPlanID }
            settings.intervalPlans.insert(watchPlan, at: 0)
        }
        return true
    }
}

/// Textos de sesiones.
enum SessionText {
    static func distance(_ meters: Double, unit: UnitSystem) -> String {
        "\(HalsynFormat.decimal(meters / unit.metersPerDistanceUnit, fractionDigits: 1)) \(unit.distanceUnitSymbol)"
    }

    /// "6 × 800 m a 4:43–4:53 /km" o "8,0 km a 6:00–6:30 /km".
    static func detail(_ session: PlannedSession, unit: UnitSystem) -> String {
        let pace = session.pace.map { "\($0.formatted(in: unit)) \(unit.paceUnitSymbol)" } ?? ""
        switch session.kind {
        case .rest:
            return String(localized: "Descanso o paseo suave")
        case .intervals:
            let repeats = session.repeats ?? 0
            let length = HalsynFormat.integer(session.repeatDistance ?? 0)
            return String(localized: "\(repeats) × \(length) m a \(pace), con 2 min de trote entre series")
        case .tempo:
            let block = distance(session.repeatDistance ?? 0, unit: unit)
            return String(localized: "\(block) continuos a \(pace), con calentamiento y vuelta a la calma")
        case .test:
            let length = distance(session.repeatDistance ?? 0, unit: unit)
            return String(localized: "Calienta 10–15 min suave sin grabar y haz 3 o 4 aceleraciones. Luego inicia el test en el reloj y corre \(length) a tope, a ritmo parejo. Cuando el reloj diga «Intervalos completados», detén el entrenamiento enseguida.")
        default:
            return String(localized: "\(distance(session.distance, unit: unit)) a \(pace)")
        }
    }
}

// MARK: - Tarjeta de SPRING

struct TrainingPlanCard: View {
    let workouts: [WorkoutSummary]
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var guidance: TrainingGuidance = .unknown
    @State private var showsSetup = false
    @State private var sent = false
    @State private var testResult: PerformanceResult?
    private var store: TrainingPlanStore { .shared }

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Plan de entrenamiento", eyebrow: HalsynModule.mal.brandName)
                if let plan = store.plan {
                    planContent(plan)
                } else {
                    Text("Elige una carrera y una fecha: HÅLSYN arma tus semanas a partir de tus carreras recientes y adapta la sesión de cada día a tu recuperación.")
                        .font(.halsynBody)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HalsynPrimaryButton("Crear plan", systemImage: "calendar.badge.plus") {
                        showsSetup = true
                    }
                }
            }
        }
        .sheet(isPresented: $showsSetup) {
            PlanSetupView(workouts: workouts)
        }
        .sheet(item: $testResult) { prefill in
            ResultEntryView(prefill: prefill) { result in
                FitnessStore.shared.add(result)
                store.applyLatestFitness(runs: workouts)
            }
        }
        .task(id: "\(model.reloadKey)|\(workouts.count)") {
            store.replanIfNeeded(runs: workouts)
            let today = Date.now
            let recovery = await model.provider.recoveryEstimates(endingOn: today, days: 1).last { Calendar.current.isDateInToday($0.day) }?.value
            let signals = await model.provider.unusualSignals(on: today, calendar: .current)
            guidance = ReadinessEngine.guidance(recovery: recovery, signals: signals)
        }
    }

    @ViewBuilder
    private func planContent(_ plan: TrainingPlan) -> some View {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: plan.goal.raceDate)).day ?? 0
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(plan.goal.distance.title))
                .font(.halsynHeadline)
            if let goal = plan.goal.goalTime {
                Text(verbatim: HalsynFormat.duration(goal))
                    .font(.halsynHeadline.monospacedDigit())
                    .foregroundStyle(.halsynAccentText)
            }
            Spacer()
            if days >= 0 {
                Text("Faltan \(days) días")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        let progress = PlanProgress.evaluate(plan: plan, runs: workouts, estimate: FitnessStore.shared.estimate(runs: workouts), today: .now, calendar: calendar)
        if progress.status != .notStarted {
            let done = SessionText.distance(progress.actualDistance, unit: unitSystem)
            let planned = SessionText.distance(progress.plannedDistance, unit: unitSystem)
            HalsynStatusIndicator(RaceGoalText.progressStatus(progress.status), text: String(localized: "\(done) de \(planned) planeados en las últimas semanas"))
        }
        if let week = plan.week(containing: .now, calendar: calendar) {
            Text("Semana \(week.index + 1) de \(plan.weeks.count) · \(String(localized: String.LocalizationValue(week.phase.title)))")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        }
        if let planned = plan.session(on: .now, calendar: calendar) {
            let adapted = PlanAdaptation.adapt(planned, guidance: guidance, paces: plan.paces)
            todaySession(adapted.session, original: planned, change: adapted.change)
        } else if plan.goal.gymWeekdays?.contains(calendar.component(.weekday, from: .now)) == true {
            Label("Hoy no hay carrera: día de gimnasio.", systemImage: "dumbbell")
                .font(.halsynBody)
                .foregroundStyle(.halsynSecondaryText)
        } else {
            Label("Hoy no hay sesión: descanso.", systemImage: "bed.double")
                .font(.halsynBody)
                .foregroundStyle(.halsynSecondaryText)
        }
        NavigationLink {
            TrainingPlanView()
        } label: {
            Label("Ver todas las semanas", systemImage: "calendar")
                .font(.halsynCaption)
        }
    }

    private func todaySession(_ session: PlannedSession, original: PlannedSession, change: PlanAdaptation.Change) -> some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            HStack(spacing: HalsynSpacing.s) {
                Image(systemName: session.kind.systemImage)
                    .foregroundStyle(session.kind.isHard ? Color.halsynHighlight : Color.halsynAccentText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoy: \(String(localized: String.LocalizationValue(session.kind.title)))")
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    Text(verbatim: SessionText.detail(session, unit: unitSystem))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            switch change {
            case .softened:
                HalsynStatusIndicator(.caution, text: "Ajustada: tu recuperación de hoy es baja, así que cambiamos la sesión dura por una suave.")
            case .rested:
                HalsynStatusIndicator(.caution, text: "Ajustada: varias señales están fuera de tu rango. Hoy toca descansar.")
            case .none:
                EmptyView()
            }
            if session.kind != .rest {
                Button {
                    sent = store.sendToWatch(session)
                } label: {
                    Label(sent ? LocalizedStringKey("Enviada al reloj") : LocalizedStringKey("Enviar al reloj"), systemImage: sent ? "checkmark.circle.fill" : "applewatch")
                }
                .buttonStyle(.bordered)
                .tint(.halsynAccent)
                if sent {
                    Text("En el reloj: SPRING › Intervalos › la sesión de hoy.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
            if session.kind == .test {
                let found = GoalCoach.testCandidate(for: original, runs: workouts, calendar: .current)
                Button {
                    testResult = found.map(PerformanceResult.init(testWorkout:))
                        ?? PerformanceResult(date: .now, distance: original.repeatDistance ?? 5000, time: 25 * 60, kind: .test)
                } label: {
                    Label(found == nil ? LocalizedStringKey("Registrar el resultado del test") : LocalizedStringKey("Guardar el test que corriste hoy"), systemImage: "stopwatch")
                }
                .buttonStyle(.borderedProminent)
                .tint(.halsynAccent)
                Text("Con el resultado se recalculan tu forma, tus ritmos y si el objetivo es alcanzable.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }
}

// MARK: - Crear plan

struct PlanSetupView: View {
    let workouts: [WorkoutSummary]
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var distance: RaceDistance = .tenK
    @State private var raceDate = Calendar.current.date(byAdding: .weekOfYear, value: 10, to: .now) ?? .now
    @State private var runsPerWeek = 4
    @State private var longRunWeekday = 1
    @State private var gymWeekdays: Set<Int> = []
    @State private var hasGoalTime = false
    @State private var goalTime: TimeInterval = 50 * 60
    @State private var enteringResult = false
    @State private var testSent = false
    @State private var testPrefill: PerformanceResult?
    private var fitness: FitnessStore { .shared }

    private var minimumDate: Date { Calendar.current.date(byAdding: .day, value: 7 * TrainingPlanGenerator.minimumWeeks, to: .now) ?? .now }
    private var maximumDate: Date { Calendar.current.date(byAdding: .day, value: 7 * TrainingPlanGenerator.maximumWeeks - 1, to: .now) ?? .now }
    private var weeklyDistance: Double { TrainingPlanGenerator.recentWeeklyDistance(workouts, endingOn: .now, calendar: .current) }

    var body: some View {
        let estimate = fitness.estimate(runs: workouts)
        NavigationStack {
            Form {
                Section {
                    Picker("Distancia", selection: $distance) {
                        ForEach(RaceDistance.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                    DatePicker("Fecha de la carrera", selection: $raceDate, in: minimumDate...maximumDate, displayedComponents: .date)
                    Toggle("Tengo un tiempo objetivo", isOn: $hasGoalTime)
                    if hasGoalTime {
                        DurationPicker(seconds: $goalTime)
                    }
                }

                fitnessSection(estimate)

                if let estimate {
                    assessmentSection(estimate)
                }

                Section {
                    Stepper(value: $runsPerWeek, in: 3...5) {
                        LabeledContent("Días de carrera por semana", value: "\(runsPerWeek)")
                    }
                    Picker("Día de la tirada larga", selection: $longRunWeekday) {
                        ForEach([7, 1], id: \.self) { weekday in
                            Text(Calendar.current.weekdaySymbols[weekday - 1].capitalized).tag(weekday)
                        }
                    }
                } header: {
                    Text("Tu semana")
                }

                Section {
                    GymWeekdayPicker(selection: $gymWeekdays)
                } header: {
                    Text("Días de gimnasio")
                } footer: {
                    Text("Las series y el umbral se ponen lejos del gimnasio: ni el mismo día ni el siguiente, que las piernas también se cansan con la fuerza.")
                }

                Section {
                } footer: {
                    Text("Partimos de tu volumen de las últimas 4 semanas y lo subimos poco a poco, con una semana más suave cada cuatro. Cada sesión tiene una distancia mínima, así que si corres poco, las primeras semanas pueden sumar algo más que tu media. Cada semana el plan se reajusta con lo que corriste de verdad, y cada 6 semanas hay un test para actualizar tus ritmos.")
                }
            }
            .navigationTitle("Nuevo plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        guard let estimate else { return }
                        let goal = PlanGoal(distance: distance, raceDate: raceDate, runsPerWeek: runsPerWeek, longRunWeekday: longRunWeekday, gymWeekdays: gymWeekdays, goalTime: hasGoalTime && goalTime > 0 ? goalTime : nil)
                        if let plan = TrainingPlanGenerator.make(goal: goal, estimate: estimate, weeklyDistance: weeklyDistance, today: .now, calendar: .current) {
                            TrainingPlanStore.shared.save(plan)
                            dismiss()
                        }
                    }
                    .disabled(estimate == nil)
                }
            }
            .sheet(isPresented: $enteringResult) {
                ResultEntryView { result in
                    FitnessStore.shared.add(result)
                }
            }
            .sheet(item: $testPrefill) { prefill in
                ResultEntryView(prefill: prefill) { result in
                    FitnessStore.shared.add(result)
                }
            }
            .onAppear {
                if !hasGoalTime { goalTime = VDOT.raceTime(vdot: estimate?.vdot ?? 40, distance: distance.rawValue).rounded() }
            }
            .onChange(of: distance) { _, newValue in
                goalTime = VDOT.raceTime(vdot: estimate?.vdot ?? 40, distance: newValue.rawValue).rounded()
            }
            .onChange(of: estimate?.vdot) { _, vdot in
                if let vdot, !hasGoalTime { goalTime = VDOT.raceTime(vdot: vdot, distance: distance.rawValue).rounded() }
            }
        }
    }

    @ViewBuilder
    private func fitnessSection(_ estimate: FitnessEstimate?) -> some View {
        Section {
            if let estimate {
                LabeledContent {
                    Text(verbatim: RaceGoalText.vdot(estimate.vdot)).monospacedDigit()
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tu forma (VDOT)")
                        Text(verbatim: RaceGoalText.source(estimate, unit: unitSystem))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Para calcular tus ritmos y si el objetivo es posible, primero hace falta medir tu forma: un test a tope o una carrera reciente.")
                    .foregroundStyle(.secondary)
            }
            Button {
                enteringResult = true
            } label: {
                Label("Registrar un test o una carrera", systemImage: "plus.circle")
            }
            if estimate == nil || estimate?.needsTest(today: .now, calendar: .current) == true {
                let testDistance = TrainingPlanGenerator.testDistance(weeklyDistance: weeklyDistance)
                Button {
                    let session = PlannedSession(date: .now, kind: .test, distance: testDistance + 3000, repeats: 1, repeatDistance: testDistance)
                    testSent = TrainingPlanStore.shared.sendToWatch(session)
                } label: {
                    Label(testSent ? LocalizedStringKey("Test enviado al reloj") : LocalizedStringKey("Hacer el test con el reloj"), systemImage: testSent ? "checkmark.circle.fill" : "stopwatch")
                }
                if testSent {
                    let length = SessionText.distance(testDistance, unit: unitSystem)
                    Text("Calienta 10–15 min suave sin grabar y haz 3 o 4 aceleraciones. Luego inicia el test en el reloj y corre \(length) a tope, a ritmo parejo. Cuando el reloj diga «Intervalos completados», detén el entrenamiento enseguida.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Si ya corriste el test hoy, se guarda con un toque.
                let todayTest = PlannedSession(date: .now, kind: .test, distance: testDistance + 3000, repeats: 1, repeatDistance: testDistance)
                if let found = GoalCoach.testCandidate(for: todayTest, runs: workouts, calendar: .current),
                   !fitness.results.contains(where: { $0.workoutID == found.id }) {
                    Button {
                        testPrefill = PerformanceResult(testWorkout: found)
                    } label: {
                        Label("Guardar el test que corriste hoy", systemImage: "stopwatch")
                    }
                }
            }
        } header: {
            Text("Tu forma actual")
        } footer: {
            if estimate?.isFromTraining == true {
                Text("Estimada con tu mejor entrenamiento reciente: probablemente se queda corta. Si creas el plan así, la primera semana empieza con un test.")
            }
        }
    }

    private func assessmentSection(_ estimate: FitnessEstimate) -> some View {
        let assessment = GoalCoach.assess(goalTime: hasGoalTime ? goalTime : nil, distance: distance, raceDate: raceDate, estimate: estimate, weeklyDistance: weeklyDistance, today: .now, calendar: .current)
        return Section {
            if let verdict = assessment.verdict {
                HalsynStatusIndicator(RaceGoalText.verdictStatus(verdict), text: RaceGoalText.verdictTitle(verdict))
            }
            Text(RaceGoalText.verdictDetail(assessment))
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Con tu forma de hoy") {
                Text(verbatim: HalsynFormat.duration(assessment.predictedTime)).monospacedDigit()
            }
            LabeledContent("Con la mejora habitual hasta la carrera") {
                Text(verbatim: HalsynFormat.duration(assessment.reachableTime)).monospacedDigit()
            }
            ForEach(Array(assessment.warnings.enumerated()), id: \.offset) { _, warning in
                Label {
                    Text(RaceGoalText.warning(warning, weekly: weeklyDistance, unit: unitSystem))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.halsynCaution)
            }
        } header: {
            Text("¿Es posible?")
        } footer: {
            Text("Mejora habitual: como mucho 1 punto de VDOT cada 4 a 6 semanas de entrenamiento constante (pauta de Daniels). Ambicioso es hasta el doble de rápido. La mejora real varía mucho entre personas.")
        }
    }
}

// MARK: - Todas las semanas

struct TrainingPlanView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var confirmingDelete = false
    @State private var runs: [WorkoutSummary]?
    @Environment(\.dismiss) private var dismiss
    private var store: TrainingPlanStore { .shared }

    var body: some View {
        HalsynScreen {
            if let plan = store.plan {
                if let runs {
                    GoalStatusCard(plan: plan, runs: runs)
                } else {
                    HalsynLoadingState()
                }
                HalsynCard {
                    VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                        HalsynSectionHeader("Tus ritmos", eyebrow: HalsynLexicon.fart.rawValue)
                        paceRow("Suave", plan.paces.easy)
                        paceRow("Umbral", plan.paces.tempo)
                        paceRow("Series", plan.paces.interval)
                        LabeledContent("Ritmo objetivo de carrera", value: "\(plan.paces.race.formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol)")
                            .font(.halsynCaption)
                    }
                }
                WeeklyVolumeChart(plan: plan, unitSystem: unitSystem)
                ForEach(plan.weeks) { week in
                    weekCard(week)
                }
                Button("Borrar plan", role: .destructive) { confirmingDelete = true }
                    .confirmationDialog("¿Borrar el plan?", isPresented: $confirmingDelete) {
                        Button("Borrar", role: .destructive) {
                            store.save(nil)
                            dismiss()
                        }
                    }
                Text("Pautas habituales de entrenamiento, no una prescripción. Si tienes dolor o una lesión, para y consulta a un profesional.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .navigationTitle("Plan de entrenamiento")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.reloadKey) {
            runs = await model.provider.recentWorkouts(limit: 120)
        }
    }

    private func paceRow(_ title: LocalizedStringKey, _ range: PaceRange) -> some View {
        LabeledContent {
            Text(verbatim: "\(range.formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol)").monospacedDigit()
        } label: {
            Text(title)
        }
        .font(.halsynCaption)
    }

    private func weekCard(_ week: PlannedWeek) -> some View {
        let isCurrent = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.contains(week.start) ?? false
        return HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HStack {
                    Text("Semana \(week.index + 1)")
                        .font(.halsynHeadline)
                    Text(LocalizedStringKey(week.phase.title))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                    Spacer()
                    Text(verbatim: SessionText.distance(week.distance, unit: unitSystem))
                        .font(.halsynCaption.monospacedDigit())
                }
                if let gym = store.plan?.goal.gymWeekdays, !gym.isEmpty {
                    Label {
                        Text(verbatim: GymWeekdayPicker.names(gym))
                    } icon: {
                        Image(systemName: "dumbbell")
                    }
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                }
                ForEach(week.sessions) { session in
                    HStack(alignment: .top, spacing: HalsynSpacing.s) {
                        Text(session.date, format: .dateTime.weekday(.abbreviated))
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                            .frame(width: 36, alignment: .leading)
                        Image(systemName: session.kind.systemImage)
                            .foregroundStyle(session.kind.isHard ? Color.halsynHighlight : Color.halsynAccentText)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(LocalizedStringKey(session.kind.title)).font(.halsynCaption.weight(.semibold))
                            Text(verbatim: SessionText.detail(session, unit: unitSystem))
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                }
            }
        }
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: HalsynRadius.card, style: .continuous)
                    .strokeBorder(Color.halsynAccent, lineWidth: 2)
            }
        }
    }
}

/// Volumen por semana: una barra por semana; la actual en color pleno y las de
/// asimilación y afinamiento más claras.
private struct WeeklyVolumeChart: View {
    let plan: TrainingPlan
    let unitSystem: UnitSystem

    var body: some View {
        let current = plan.week(containing: .now, calendar: .current)?.index
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Volumen por semana", eyebrow: HalsynLexicon.tid.rawValue)
                Chart(plan.weeks) { week in
                    BarMark(
                        x: .value("Semana", week.index + 1),
                        y: .value("Distancia", week.distance / unitSystem.metersPerDistanceUnit)
                    )
                    .cornerRadius(3)
                    .foregroundStyle(week.index == current ? Color.halsynHighlight : Color.halsynChart.opacity(week.phase == .recovery || week.phase == .taper ? 0.45 : 0.85))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { AxisValueLabel() }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(Color.halsynHairline)
                        AxisValueLabel()
                    }
                }
                .frame(height: 150)
                .accessibilityLabel(Text("Volumen por semana"))
                Text(verbatim: unitSystem.distanceUnitSymbol)
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }
}

/// Días de la semana como fichas (lunes primero).
struct GymWeekdayPicker: View {
    @Binding var selection: Set<Int>

    /// 2 = lunes … 7 = sábado, 1 = domingo.
    static let order = [2, 3, 4, 5, 6, 7, 1]

    static func names(_ days: Set<Int>) -> String {
        order.filter(days.contains).map { Calendar.current.shortWeekdaySymbols[$0 - 1].capitalized }.formatted(.list(type: .and))
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.order, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    if isOn { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(verbatim: String(Calendar.current.veryShortWeekdaySymbols[weekday - 1]))
                        .font(.halsynCaption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isOn ? Color.halsynSurface : Color.halsynPrimaryText)
                        .background(Circle().fill(isOn ? Color.halsynAccentText : Color.halsynHairline.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: Calendar.current.weekdaySymbols[weekday - 1]))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
