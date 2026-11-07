import HalsynCore
import HalsynDesign
import SwiftUI

/// Lo que decidiste a mano sobre registros dudosos: usarlos o no en los cálculos.
@MainActor
@Observable
final class WorkoutQualityStore {
    static let shared = WorkoutQualityStore()
    static let excludedKey = "halsyn.quality.excluded"
    static let includedKey = "halsyn.quality.included"

    private(set) var excluded: Set<UUID>
    private(set) var included: Set<UUID>
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        excluded = Set((defaults.stringArray(forKey: Self.excludedKey) ?? []).compactMap(UUID.init(uuidString:)))
        included = Set((defaults.stringArray(forKey: Self.includedKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    /// Sin duplicados, superposiciones ni lo que excluiste (para volumen, carga y plan).
    func clean(_ workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        DataQuality.clean(workouts, excluded: excluded, included: included)
    }

    /// `true` = se usa en los cálculos.
    func isUsed(_ workout: WorkoutSummary, quality: WorkoutQuality?) -> Bool {
        if excluded.contains(workout.id) { return false }
        if included.contains(workout.id) { return true }
        return quality?.level != .excluded
    }

    func setUsed(_ used: Bool, for workout: WorkoutSummary, quality: WorkoutQuality?) {
        excluded.remove(workout.id)
        included.remove(workout.id)
        let automatic = quality?.level != .excluded
        if used != automatic {
            if used { included.insert(workout.id) } else { excluded.insert(workout.id) }
        }
        defaults.set(excluded.map(\.uuidString), forKey: Self.excludedKey)
        defaults.set(included.map(\.uuidString), forKey: Self.includedKey)
    }
}

enum DataQualityText {
    static func reason(_ flag: WorkoutQualityFlag) -> LocalizedStringKey {
        switch flag {
        case .duplicate: "Duplicado: el mismo entrenamiento está dos veces"
        case let .overlaps(_, otherSource):
            otherSource ? "Se superpone con otro registro de otra app" : "Se superpone con otro registro"
        case .missingDistance: "Sin distancia: no sirve para ritmo ni forma"
        case .tooShort: "Muy corto (menos de 2 min o 200 m)"
        case .implausiblePace: "Ritmo imposible: probable error de GPS o de distancia"
        case .implausibleHeartRate: "Pulso imposible: no se usa su frecuencia cardíaca"
        case .zeroCadence: "Cadencia 0: se ignora"
        case .implausibleCadence: "Cadencia imposible: se ignora"
        }
    }

    static func level(_ level: WorkoutQuality.Level) -> (String, HalsynStatusIndicator.Level) {
        switch level {
        case .valid: (String(localized: "Válido"), .positive)
        case .doubtful: (String(localized: "Dudoso: no cuenta para la forma ni las predicciones"), .caution)
        case .excluded: (String(localized: "Fuera de los cálculos"), .alert)
        }
    }
}

/// Registros con algo raro: por qué y si se usan. Nada se borra de Salud.
struct DataQualityView: View {
    let workouts: [WorkoutSummary]
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    private var store: WorkoutQualityStore { .shared }

    var body: some View {
        let quality = DataQuality.assess(workouts)
        let flagged = workouts.filter { quality[$0.id]?.needsReview == true }
        Form {
            Section {
                Text("HÅLSYN revisa tus entrenamientos antes de calcular tu forma, tus predicciones y tu plan. Los registros dudosos no se borran de Salud: solo dejan de contar donde podrían confundir. Puedes decidir tú si se usan.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
            if flagged.isEmpty {
                Section {
                    Label("No hay nada para revisar", systemImage: "checkmark.seal")
                        .foregroundStyle(.halsynPositive)
                }
            } else {
                Section {
                    ForEach(flagged) { workout in
                        row(workout, quality: quality[workout.id])
                    }
                } header: {
                    Text("Para revisar (\(String(flagged.count)))")
                }
            }
        }
        .navigationTitle("Calidad de los datos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ workout: WorkoutSummary, quality: WorkoutQuality?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(LocalizedStringKey(workout.activity.title))
                } icon: {
                    Image(systemName: workout.activity.systemImage)
                }
                .font(.halsynHeadline)
                Spacer()
                Text(workout.start, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
            Text(verbatim: summary(workout))
                .font(.halsynCaption.monospacedDigit())
                .foregroundStyle(.halsynSecondaryText)
            ForEach(Array((quality?.flags ?? []).enumerated()), id: \.offset) { _, flag in
                Label(DataQualityText.reason(flag), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.halsynCaution)
            }
            if let level = quality?.level {
                let text = DataQualityText.level(level)
                HalsynStatusIndicator(text.1, text: text.0)
            }
            Toggle("Usar en los cálculos", isOn: Binding(
                get: { store.isUsed(workout, quality: quality) },
                set: { store.setUsed($0, for: workout, quality: quality) }
            ))
            .font(.halsynCaption)
        }
        .padding(.vertical, 4)
    }

    private func summary(_ workout: WorkoutSummary) -> String {
        var parts: [String] = []
        if let distance = workout.distanceMeters, distance > 0 { parts.append(SessionText.distance(distance, unit: unitSystem)) }
        parts.append(HalsynFormat.duration(workout.duration))
        if let pace = workout.averagePace { parts.append("\(pace.formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol)") }
        if let heartRate = workout.averageHeartRate { parts.append("\(Int(heartRate.rounded())) " + String(localized: "lpm")) }
        if case let .healthKit(source?) = workout.origin { parts.append(source) }
        return parts.joined(separator: " · ")
    }
}
