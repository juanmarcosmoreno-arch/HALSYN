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
        .task(id: model.reloadKey) {
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
            Spacer()
            if days >= 0 {
                Text("Faltan \(days) días")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        if let week = plan.week(containing: .now, calendar: calendar) {
            Text("Semana \(week.index + 1) de \(plan.weeks.count) · \(String(localized: String.LocalizationValue(week.phase.title)))")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        }
        if let planned = plan.session(on: .now, calendar: calendar) {
            let adapted = PlanAdaptation.adapt(planned, guidance: guidance, paces: plan.paces)
            todaySession(adapted.session, original: planned, change: adapted.change)
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
        }
    }
}

// MARK: - Crear plan

struct PlanSetupView: View {
    let workouts: [WorkoutSummary]
    @Environment(\.dismiss) private var dismiss
    @State private var distance: RaceDistance = .tenK
    @State private var raceDate = Calendar.current.date(byAdding: .weekOfYear, value: 10, to: .now) ?? .now
    @State private var runsPerWeek = 4
    @State private var longRunWeekday = 1
    @State private var failed = false

    private var minimumDate: Date { Calendar.current.date(byAdding: .day, value: 7 * TrainingPlanGenerator.minimumWeeks, to: .now) ?? .now }
    private var maximumDate: Date { Calendar.current.date(byAdding: .day, value: 7 * TrainingPlanGenerator.maximumWeeks, to: .now) ?? .now }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Distancia", selection: $distance) {
                        ForEach(RaceDistance.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                    DatePicker("Fecha de la carrera", selection: $raceDate, in: minimumDate...maximumDate, displayedComponents: .date)
                    Stepper(value: $runsPerWeek, in: 3...5) {
                        LabeledContent("Días de carrera por semana", value: "\(runsPerWeek)")
                    }
                    Picker("Día de la tirada larga", selection: $longRunWeekday) {
                        ForEach([7, 1], id: \.self) { weekday in
                            Text(Calendar.current.weekdaySymbols[weekday - 1].capitalized).tag(weekday)
                        }
                    }
                } footer: {
                    if failed {
                        Text("Hacen falta 3 carreras de 3 km o más en los últimos 90 días para calcular tus ritmos. Sal a correr con el reloj y vuelve a intentarlo.")
                    } else {
                        Text("Partimos de tu volumen de las últimas 4 semanas y subimos como mucho un 8 por ciento por semana, con una semana más suave cada cuatro. Los ritmos salen de tus carreras recientes.")
                    }
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
                        let goal = PlanGoal(distance: distance, raceDate: raceDate, runsPerWeek: runsPerWeek, longRunWeekday: longRunWeekday)
                        if let plan = TrainingPlanGenerator.make(goal: goal, runs: workouts, today: .now, calendar: .current) {
                            TrainingPlanStore.shared.save(plan)
                            dismiss()
                        } else {
                            failed = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Todas las semanas

struct TrainingPlanView: View {
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    private var store: TrainingPlanStore { .shared }

    var body: some View {
        HalsynScreen {
            if let plan = store.plan {
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
