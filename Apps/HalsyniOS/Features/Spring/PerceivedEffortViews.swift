import HalsynCore
import HalsynDesign
import SwiftUI

/// Esfuerzo percibido (RPE 1–10, Borg CR-10) que anotas en cada entrenamiento.
/// Se guarda aparte de la intensidad fisiológica: no la reemplaza.
@MainActor
@Observable
final class PerceivedEffortStore {
    static let shared = PerceivedEffortStore()
    static let key = "halsyn.perceivedEffort"

    private(set) var values: [UUID: Int]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
        var result: [UUID: Int] = [:]
        for (key, value) in stored {
            if let id = UUID(uuidString: key), (1...10).contains(value) { result[id] = value }
        }
        values = result
    }

    func rpe(for id: UUID) -> Int? { values[id] }

    func set(_ rpe: Int?, for id: UUID) {
        values[id] = rpe.flatMap { (1...10).contains($0) ? $0 : nil }
        var stored: [String: Int] = [:]
        for (id, value) in values { stored[id.uuidString] = value }
        defaults.set(stored, forKey: Self.key)
    }
}

enum PerceivedEffortText {
    /// Descriptor de la escala CR-10 de Borg.
    static func descriptor(_ rpe: Int) -> String {
        switch rpe {
        case ...2: String(localized: "muy suave")
        case 3...4: String(localized: "suave")
        case 5...6: String(localized: "algo duro")
        case 7...8: String(localized: "duro")
        default: String(localized: "máximo o casi")
        }
    }

    static func compliance(_ compliance: WorkoutIntensity.PlanCompliance) -> String? {
        switch compliance {
        case .notApplicable: nil
        case .asPlanned: String(localized: "Hecha como estaba planificada.")
        case .harder: String(localized: "Más intensa que lo planificado.")
        case .easier: String(localized: "Más suave que lo planificado.")
        }
    }
}

/// Selector del RPE en el detalle del entrenamiento.
struct PerceivedEffortCard: View {
    let workout: WorkoutSummary
    let intensity: WorkoutIntensity?
    private var store: PerceivedEffortStore { .shared }

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                Label("Esfuerzo percibido", systemImage: "figure.run.circle")
                    .halsynEyebrowStyle()
                let current = store.rpe(for: workout.id)
                HStack(spacing: 4) {
                    ForEach(1...10, id: \.self) { value in
                        Button {
                            store.set(current == value ? nil : value, for: workout.id)
                        } label: {
                            Text(verbatim: String(value))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(current == value ? Color.halsynAccent.opacity(0.25) : Color.halsynSecondaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: "RPE \(value)"))  // nolocalize
                    }
                }
                if let current {
                    let descriptor = PerceivedEffortText.descriptor(current)
                    Text("RPE \(String(current)) de 10: \(descriptor).")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                    if let intensity, intensity.perceptionDiffers, intensity.kind != .unknown {
                        let physiological = IntensityText.title(intensity.kind)
                        Text("Tu pulso indica «\(physiological)», pero lo sentiste distinto. No es un error: el cansancio, el calor o el sueño cambian la percepción. Se guardan las dos cosas por separado.")
                            .font(.caption2)
                            .foregroundStyle(.halsynCaution)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Opcional. 1 = muy suave, 10 = máximo (escala de Borg CR-10). Se usa para clasificar la sesión solo cuando no hay pulso ni ritmo.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let intensity, let compliance = PerceivedEffortText.compliance(intensity.planCompliance) {
                    Text(verbatim: compliance)
                        .font(.caption2)
                        .foregroundStyle(intensity.planCompliance == .asPlanned ? Color.halsynSecondaryText : Color.halsynCaution)
                }
            }
        }
    }
}
