import HalsynCore
import HalsynDesign
import SwiftUI

// MARK: - Molestias

/// Molestias registradas (para que el plan se adapte). Solo en este iPhone y en tu copia de iCloud.
@MainActor
@Observable
final class ComplaintStore {
    static let shared = ComplaintStore()
    static let key = "halsyn.complaints"

    private(set) var complaints: [Complaint]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        complaints = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Complaint].self, from: $0) } ?? []
    }

    var active: [Complaint] {
        complaints.filter { $0.isActive(on: .now, calendar: .current) }.sorted { $0.date > $1.date }
    }

    func add(_ complaint: Complaint) {
        complaints.append(complaint)
        persist()
        TrainingPlanStore.shared.refreshAdvice()
    }

    func resolve(_ id: UUID) {
        guard let index = complaints.firstIndex(where: { $0.id == id }) else { return }
        complaints[index].resolvedAt = .now
        persist()
        TrainingPlanStore.shared.refreshAdvice()
    }

    private func persist() {
        // Se guardan los últimos 180 días.
        let limit = Calendar.current.date(byAdding: .day, value: -180, to: .now) ?? .now
        complaints.removeAll { $0.date < limit }
        if let data = try? JSONEncoder().encode(complaints) { defaults.set(data, forKey: Self.key) }
    }
}

// MARK: - Textos

enum PlanAdviceText {
    static func reason(_ reason: PlanAdvice.Reason) -> String {
        switch reason {
        case let .lowRecovery(lowDays, recent, usual):
            return String(localized: "Tu recuperación estuvo baja \(String(lowDays)) de los últimos 3 días (media \(String(recent)); lo habitual en ti es \(String(usual))).")
        case let .volumeSpike(ratio):
            let percent = String(Int(((ratio - 1) * 100).rounded()))
            return String(localized: "Corriste un \(percent) % más kilómetros esta semana que tu media de las 4 anteriores.")
        case let .manyHardSessions(count):
            return String(localized: "Hiciste \(String(count)) sesiones exigentes (pulso alto) en los últimos 7 días.")
        case let .complaint(area, pain):
            let zone = String(localized: String.LocalizationValue(area.title))
            return String(localized: "Registraste una molestia en \(zone) (\(String(pain))/10): se quita la intensidad mientras dure.")
        case let .severeComplaint(area, pain):
            let zone = String(localized: String.LocalizationValue(area.title))
            return String(localized: "Registraste dolor en \(zone) (\(String(pain))/10): descanso unos días. Si no mejora o empeora, consulta a un profesional.")
        case .consecutiveHardDays:
            return String(localized: "Había dos sesiones exigentes en días seguidos: la segunda pasa a suave para que puedas asimilar la primera.")
        }
    }

    static func change(_ adjustment: PlanAdvice.Adjustment, unit: UnitSystem) -> String {
        let from = String(localized: String.LocalizationValue(adjustment.original.kind.title))
        let to = String(localized: String.LocalizationValue(adjustment.adjusted.kind.title))
        switch adjustment.change {
        case .rested:
            return String(localized: "\(from) → descanso")
        case .softened:
            return String(localized: "\(from) → \(to) de \(SessionText.distance(adjustment.adjusted.distance, unit: unit))")
        case .shortened:
            return String(localized: "\(from): \(SessionText.distance(adjustment.original.distance, unit: unit)) → \(SessionText.distance(adjustment.adjusted.distance, unit: unit))")
        }
    }
}

// MARK: - Ajustes automáticos

/// Qué cambió en los próximos días y por qué, con la opción de mantener el plan original.
struct PlanAdviceView: View {
    let advice: PlanAdvice
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    private var store: TrainingPlanStore { .shared }

    var body: some View {
        let rejected = store.isRejected(advice)
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            Label(rejected ? LocalizedStringKey("Ajustes sugeridos (no aplicados)") : LocalizedStringKey("Ajustes automáticos de estos días"), systemImage: "wand.and.stars")
                .font(.halsynCaption.weight(.semibold))
                .foregroundStyle(rejected ? Color.halsynSecondaryText : Color.halsynCaution)
            ForEach(Array(advice.reasons.enumerated()), id: \.offset) { _, reason in
                Text(verbatim: "· " + PlanAdviceText.reason(reason))
                    .font(.caption)
                    .foregroundStyle(.halsynPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(advice.adjustments) { adjustment in
                HStack(alignment: .firstTextBaseline) {
                    Text(adjustment.original.date, format: .dateTime.weekday(.abbreviated).day())
                        .font(.caption.weight(.semibold))
                        .frame(width: 56, alignment: .leading)
                    Text(verbatim: PlanAdviceText.change(adjustment, unit: unitSystem))
                        .font(.caption)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
            Button {
                store.setRejected(!rejected)
            } label: {
                Text(rejected ? LocalizedStringKey("Aplicar los ajustes") : LocalizedStringKey("Mantener el plan original"))
                    .font(.halsynCaption.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(HalsynSpacing.m)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.halsynCaution.opacity(rejected ? 0.04 : 0.1)))
    }
}

// MARK: - Fila de molestias en la tarjeta

struct ComplaintRow: View {
    @State private var adding = false
    private var store: ComplaintStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            ForEach(store.active) { complaint in
                HStack {
                    Label {
                        Text(verbatim: "\(String(localized: String.LocalizationValue(complaint.area.title))) · \(complaint.pain)/10")
                    } icon: {
                        Image(systemName: "bandage")
                    }
                    .font(.halsynCaption)
                    .foregroundStyle(complaint.pain >= 7 ? Color.halsynAlert : Color.halsynCaution)
                    Spacer()
                    Button("Ya está bien") { store.resolve(complaint.id) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            Button {
                adding = true
            } label: {
                Label("Registrar una molestia", systemImage: "bandage")
                    .font(.halsynCaption)
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $adding) {
            ComplaintEntryView()
        }
    }
}

struct ComplaintEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var area: Complaint.Area = .knee
    @State private var pain = 3.0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Zona", selection: $area) {
                        ForEach(Complaint.Area.allCases) { area in
                            Text(LocalizedStringKey(area.title)).tag(area)
                        }
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("Intensidad", value: "\(Int(pain))/10")
                        Slider(value: $pain, in: 0...10, step: 1)
                    }
                    TextField("Nota (opcional)", text: $note, axis: .vertical)
                } footer: {
                    Text("Con 4 o más, el plan quita la intensidad mientras dure (hasta 14 días o hasta que marques que ya está bien). Con 7 o más, propone descanso. HÅLSYN no diagnostica: si el dolor es fuerte, aparece de golpe o no mejora, consulta a un profesional.")
                }
            }
            .navigationTitle("Molestia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        ComplaintStore.shared.add(Complaint(date: .now, area: area, pain: Int(pain), note: text.isEmpty ? nil : text))
                        dismiss()
                    }
                }
            }
        }
    }
}
