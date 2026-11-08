import HalsynCore
import HalsynDesign
import Observation
import SwiftUI

/// Eventos de salud que registras (enfermedad, medicación, lesión…). Solo en
/// este iPhone (y en tu copia de iCloud, si la activaste).
@MainActor
@Observable
final class HealthEventStore {
    static let shared = HealthEventStore()
    static let key = "halsyn.healthEvents"

    private(set) var events: [HealthEvent]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        events = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([HealthEvent].self, from: $0) } ?? []
    }

    func save(_ event: HealthEvent) {
        events.removeAll { $0.id == event.id }
        events.append(event)
        events.sort { $0.start > $1.start }
        persist()
    }

    func remove(_ id: UUID) {
        events.removeAll { $0.id == id }
        persist()
    }

    /// Días que impedían entrenar (enfermedad, fiebre, lesión).
    func trainingAffectedDays(today: Date = .now) -> Set<Date> {
        events.trainingAffectedDays(today: today, calendar: .current)
    }

    /// Eventos dentro de un período, para marcarlos en una gráfica.
    func spans(from start: Date, to end: Date) -> [HalsynEventSpan] {
        events.overlapping(from: start, to: end, today: .now, calendar: .current).map { event in
            HalsynEventSpan(id: event.id, title: event.title.isEmpty ? String(localized: String.LocalizationValue(event.kind.title)) : event.title, start: Calendar.current.startOfDay(for: event.start), end: event.lastDay(today: .now, calendar: .current), systemImage: event.kind.systemImage)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) { defaults.set(data, forKey: Self.key) }
        IntensityContext.updateRecoveryContext()
    }
}

/// Motivo de las sesiones del plan que no hiciste.
@MainActor
@Observable
final class SessionSkipStore {
    static let shared = SessionSkipStore()
    static let key = "halsyn.sessionSkips"

    private(set) var skips: [Date: SessionSkipReason]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        var result: [Date: SessionSkipReason] = [:]
        for (key, value) in stored {
            if let seconds = Double(key), let reason = SessionSkipReason(rawValue: value) {
                result[Date(timeIntervalSince1970: seconds)] = reason
            }
        }
        skips = result
    }

    func reason(for day: Date) -> SessionSkipReason? {
        skips[Calendar.current.startOfDay(for: day)]
    }

    func set(_ reason: SessionSkipReason?, for day: Date) {
        let key = Calendar.current.startOfDay(for: day)
        skips[key] = reason
        var stored: [String: String] = [:]
        for (date, value) in skips { stored[String(Int(date.timeIntervalSince1970))] = value.rawValue }
        defaults.set(stored, forKey: Self.key)
    }
}

extension GoalProbability {
    /// Con los motivos de las sesiones no hechas y tus eventos de salud.
    @MainActor
    static func evaluateInApp(plan: TrainingPlan, performance: PerformanceAssessment?, runs: [WorkoutSummary], today: Date, calendar: Calendar) -> GoalProbability? {
        let blocked = HealthEventStore.shared.events.blockedFutureDays(today: today, until: plan.goal.raceDate, calendar: calendar)
        return evaluate(plan: plan, performance: performance, runs: runs, today: today, calendar: calendar, skips: SessionSkipStore.shared.skips, healthDays: HealthEventStore.shared.trainingAffectedDays(today: today), blockedFutureDays: blocked)
    }
}

enum SessionSkipText {
    static func title(_ reason: SessionSkipReason) -> LocalizedStringKey {
        switch reason {
        case .illness: "Enfermedad"
        case .injury: "Lesión o dolor"
        case .travel: "Viaje"
        case .time: "Falta de tiempo"
        case .other: "Otro motivo"
        }
    }

    static func systemImage(_ reason: SessionSkipReason) -> String {
        switch reason {
        case .illness: "allergens"
        case .injury: "bandage"
        case .travel: "airplane"
        case .time: "clock"
        case .other: "ellipsis.circle"
        }
    }
}

// MARK: - Lista

/// Registro de eventos de salud, con fechas de inicio y fin.
struct HealthEventListView: View {
    @State private var editing: HealthEvent?
    private var store: HealthEventStore { .shared }

    var body: some View {
        List {
            Section {
                Button {
                    editing = HealthEvent(kind: .illness, title: "", start: .now)
                } label: {
                    Label("Registrar un evento", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Enfermedades, síntomas, fiebre, medicación, lesiones, vacunas, estrés fuera de lo común o días de recuperación. Se marcan en las gráficas como contexto. HÅLSYN no diagnostica ni dice que un evento causó un cambio: solo te ayuda a recordarlo al mirar tus tendencias. Con enfermedad, fiebre o lesión, las sesiones de esos días no cuentan como incumplidas y el plan baja la intensidad.")
            }
            if !store.events.isEmpty {
                Section("Registrados") {
                    ForEach(store.events) { event in
                        Button {
                            editing = event
                        } label: {
                            HealthEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Borrar", role: .destructive) { store.remove(event.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Eventos de salud")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { event in
            NavigationStack {
                HealthEventEditor(event: event)
            }
        }
    }
}

struct HealthEventRow: View {
    let event: HealthEvent

    var body: some View {
        HStack(spacing: HalsynSpacing.m) {
            Image(systemName: event.kind.systemImage)
                .foregroundStyle(.halsynAccentText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.title.isEmpty ? String(localized: String.LocalizationValue(event.kind.title)) : event.title)
                    .font(.halsynCaption.weight(.semibold))
                    .foregroundStyle(.halsynPrimaryText)
                Text(verbatim: HealthEventText.period(event))
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

enum HealthEventText {
    static func period(_ event: HealthEvent) -> String {
        let start = event.start.formatted(.dateTime.day().month(.abbreviated).year())
        guard let end = event.end else { return String(localized: "Desde el \(start) · en curso") }
        if Calendar.current.isDate(end, inSameDayAs: event.start) { return start }
        let endText = end.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(start) – \(endText)"
    }
}

struct HealthEventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var event: HealthEvent
    @State private var hasEnd: Bool
    @State private var end: Date

    init(event: HealthEvent) {
        _event = State(initialValue: event)
        _hasEnd = State(initialValue: event.end != nil)
        _end = State(initialValue: event.end ?? event.start)
    }

    var body: some View {
        Form {
            Section {
                Picker("Tipo", selection: $event.kind) {
                    ForEach(HealthEvent.Kind.allCases) { kind in
                        Label(LocalizedStringKey(kind.title), systemImage: kind.systemImage).tag(kind)
                    }
                }
                TextField("Nombre (p. ej. sinusitis)", text: $event.title)
            }
            Section {
                DatePicker("Inicio", selection: $event.start, in: ...Date.now, displayedComponents: .date)
                Toggle("Ya terminó", isOn: $hasEnd)
                if hasEnd {
                    DatePicker("Fin", selection: $end, in: event.start..., displayedComponents: .date)
                }
            }
            Section("Nota") {
                TextField("Opcional", text: Binding(get: { event.note ?? "" }, set: { event.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
            }
        }
        .navigationTitle("Evento de salud")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    var saved = event
                    saved.end = hasEnd ? max(end, event.start) : nil
                    HealthEventStore.shared.save(saved)
                    dismiss()
                }
            }
        }
    }
}
