import HalsynCore
import HalsynDesign
import SwiftUI

/// Crear o editar un objetivo.
struct GoalEditorView: View {
    let original: GoalDefinition?
    let data: GoalData?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var draft: GoalDefinition
    @State private var usesProgression: Bool
    @State private var progressionStart: Double
    @State private var reminderOn: Bool
    @State private var reminderTime: Date
    @State private var reminderDays: Set<Int>
    @State private var confirmingDelete = false

    private var store: GoalStore { .shared }

    init(goal: GoalDefinition?, data: GoalData?) {
        original = goal
        self.data = data
        let base = goal ?? GoalDefinition(kind: .steps, period: .daily, target: 8000)
        _draft = State(initialValue: base)
        _usesProgression = State(initialValue: base.progression != nil)
        _progressionStart = State(initialValue: base.progression?.startValue ?? max(base.target / 2, 1000))
        _reminderOn = State(initialValue: base.reminder != nil)
        let minutes = base.reminder?.minutes ?? 19 * 60
        _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now)
        _reminderDays = State(initialValue: base.reminder?.weekdays ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Qué quieres conseguir") {
                    Picker("Tipo", selection: kindBinding) {
                        ForEach(GoalKind.allCases) { kind in
                            Label(LocalizedStringKey(kind.title), systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    Picker("Periodo", selection: periodBinding) {
                        ForEach(draft.kind.allowedPeriods) { period in
                            Text(verbatim: GoalText.period(period)).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper {
                        LabeledContent(usesProgression ? "Meta final" : "Objetivo") {
                            Text(verbatim: GoalText.value(draft.target, draft.kind, unit: unitSystem))
                                .monospacedDigit()
                        }
                    } onIncrement: {
                        adjust(&draft.target, by: 1)
                    } onDecrement: {
                        adjust(&draft.target, by: -1)
                    }
                    if let average = recentAverage {
                        Button {
                            draft.target = rounded(average)
                        } label: {
                            Label("Usar tu media reciente: \(GoalText.value(average, draft.kind, unit: unitSystem))", systemImage: "wand.and.stars")
                        }
                    }
                }

                if draft.kind == .runningDistance && draft.period == .weekly {
                    Section {
                        Toggle("Aumentar poco a poco", isOn: $usesProgression)
                        if usesProgression {
                            Stepper {
                                LabeledContent("Empezar en") {
                                    Text(verbatim: GoalText.value(progressionStart, draft.kind, unit: unitSystem)).monospacedDigit()
                                }
                            } onIncrement: {
                                adjust(&progressionStart, by: 1)
                            } onDecrement: {
                                adjust(&progressionStart, by: -1)
                            }
                            let plan = GoalProgression(startValue: progressionStart, endValue: draft.target, startDate: draft.progression?.startDate ?? .now)
                            let weeks = plan.weeksToReachEnd
                            Text("Llegarás a la meta en \(weeks) semanas, subiendo como mucho un 10 por ciento por semana.")
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    } footer: {
                        Text("Subir el volumen de forma gradual es una pauta prudente habitual en running. No garantiza evitar lesiones: escucha a tu cuerpo.")
                    }
                }

                Section {
                    Toggle("Recordatorio", isOn: $reminderOn)
                    if reminderOn {
                        DatePicker("Hora", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        WeekdayPicker(selection: $reminderDays)
                    }
                } footer: {
                    Text(reminderOn ? "Sin días marcados, todos los días. El aviso solo nombra el objetivo, nunca tus datos." : "Opcional.")
                }

                if let original {
                    Section {
                        Button("Eliminar objetivo", role: .destructive) { confirmingDelete = true }
                    }
                    .confirmationDialog("¿Eliminar este objetivo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Eliminar", role: .destructive) {
                            store.delete(original)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? LocalizedStringKey("Nuevo objetivo") : LocalizedStringKey("Editar objetivo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(draft.target <= 0)
                }
            }
        }
    }

    // MARK: Lógica

    private var kindBinding: Binding<GoalKind> {
        Binding(get: { draft.kind }, set: { kind in
            let period = kind.allowedPeriods.contains(draft.period) ? draft.period : (kind.allowedPeriods.first ?? .weekly)
            let template = GoalDefinition.templates.first { $0.kind == kind }
            draft = GoalDefinition(id: draft.id, kind: kind, period: period, target: suggestedTarget(kind, period: period, template: template), reminder: draft.reminder, createdAt: draft.createdAt)
            usesProgression = false
        })
    }

    private var periodBinding: Binding<Goal.Period> {
        Binding(get: { draft.period }, set: { period in
            let factor = scale(from: draft.period, to: period)
            var copy = draft
            copy.period = period
            copy.target = draft.kind.isAverage || draft.kind == .runs ? draft.target : rounded(draft.target * factor)
            copy.target = min(max(copy.target, GoalText.range(draft.kind, period: period).lowerBound), GoalText.range(draft.kind, period: period).upperBound)
            draft = copy
        })
    }

    private func suggestedTarget(_ kind: GoalKind, period: Goal.Period, template: GoalDefinition?) -> Double {
        if let template, template.period == period { return template.target }
        if let template, !kind.isAverage, kind != .runs {
            return rounded(template.target * scale(from: template.period, to: period))
        }
        return template?.target ?? GoalText.range(kind, period: period).lowerBound
    }

    private func scale(from: Goal.Period, to: Goal.Period) -> Double {
        func days(_ period: Goal.Period) -> Double { period == .daily ? 1 : (period == .weekly ? 7 : 30) }
        return days(to) / days(from)
    }

    private func adjust(_ value: inout Double, by direction: Double) {
        let step = GoalText.step(draft.kind, unit: unitSystem) * (draft.period == .monthly && !draft.kind.isAverage && draft.kind != .runs ? 4 : 1)
        let range = GoalText.range(draft.kind, period: draft.period)
        value = min(max(rounded(value) + step * direction, range.lowerBound), range.upperBound)
    }

    private func rounded(_ value: Double) -> Double {
        let step = GoalText.step(draft.kind, unit: unitSystem)
        return (value / step).rounded() * step
    }

    /// Media de las últimas 4 semanas, en la escala del periodo (para sugerir un objetivo realista).
    private var recentAverage: Double? {
        guard let data else { return nil }
        let evaluator = GoalEvaluator(calendar: .current)
        let template = GoalDefinition(kind: draft.kind, period: draft.period, target: 1)
        let count = draft.period == .daily ? 28 : (draft.period == .weekly ? 4 : 3)
        let history = evaluator.history(template, data: data, now: .now, count: count).filter(\.hasData)
        guard history.count >= max(count / 2, 2) else { return nil }
        return history.map(\.value).reduce(0, +) / Double(history.count)
    }

    private func save() {
        var goal = draft
        goal.progression = usesProgression && goal.kind == .runningDistance && goal.period == .weekly
            ? GoalProgression(startValue: min(progressionStart, goal.target), endValue: goal.target, startDate: draft.progression?.startDate ?? .now)
            : nil
        if reminderOn {
            let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            goal.reminder = GoalReminder(weekdays: reminderDays, minutes: (components.hour ?? 19) * 60 + (components.minute ?? 0))
        } else {
            goal.reminder = nil
        }
        store.save(goal)
        dismiss()
    }
}

/// Selector de días de la semana en el orden local.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let selected = selection.contains(weekday)
                Button {
                    if selected { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(verbatim: calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Circle().fill(selected ? Color.halsynAccent : Color.halsynHairline.opacity(0.6)))
                        .foregroundStyle(selected ? Color.white : Color.halsynPrimaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: calendar.weekdaySymbols[weekday - 1]))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
