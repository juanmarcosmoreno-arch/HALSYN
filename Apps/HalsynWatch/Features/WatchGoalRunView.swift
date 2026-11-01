import HalsynCore
import HalsynDesign
import SwiftUI

/// Carrera libre con objetivo: distancia (el anillo dice cuánto falta) y/o
/// ritmo (el anillo se pone rojo si vas más lento, verde en ritmo). Recuerda
/// la última elección.
struct WatchGoalRunView: View {
    @Environment(WorkoutManager.self) private var workout
    @AppStorage("halsyn.watch.goalDistance") private var distance: Double = 5000
    @AppStorage("halsyn.watch.goalUsesPace") private var usesPace = false
    /// Segundos por kilómetro.
    @AppStorage("halsyn.watch.goalPace") private var paceSeconds: Double = 330

    private var unitSystem: UnitSystem { RunSettingsStore.shared.settings.unitSystem }
    static let distances: [Double] = [0, 3000, 5000, 8000, 10_000, 15_000, 21_097.5, 42_195]

    /// Ritmos de 3:00 a 9:00 por unidad, de 5 en 5 segundos, guardados en s/km.
    private var paceOptions: [Double] {
        let perUnit = unitSystem.metersPerDistanceUnit / 1000
        return stride(from: 180.0, through: 540.0, by: 5).map { ($0 / perUnit).rounded() }
    }

    private var plan: IntervalPlan? {
        IntervalPlan.goalRun(
            distance: distance,
            pace: usesPace ? Pace(secondsPerKilometer: paceSeconds) : nil,
            name: String(localized: "Carrera con objetivo")
        )
    }

    var body: some View {
        List {
            Picker("Distancia", selection: $distance) {
                ForEach(Self.distances, id: \.self) { meters in
                    Text(verbatim: distanceTitle(meters)).tag(meters)
                }
            }
            Toggle("Ritmo objetivo", isOn: $usesPace)
            if usesPace {
                Picker("Ritmo", selection: Binding(get: { nearestPace }, set: { paceSeconds = $0 })) {
                    ForEach(paceOptions, id: \.self) { seconds in
                        Text(verbatim: "\(Pace(secondsPerKilometer: seconds).formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol)").tag(seconds)
                    }
                }
            }
            Section {
                Button {
                    if let plan { Task { await workout.start(indoor: false, plan: plan) } }
                } label: {
                    Label("Empezar", systemImage: "figure.run")
                }
                .disabled(plan == nil)
                .listRowBackground(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(HalsynPalette.darkPrimary)))
                Button {
                    if let plan { Task { await workout.start(indoor: true, plan: plan) } }
                } label: {
                    Label("En cinta", systemImage: "figure.run.treadmill")
                }
                .disabled(plan == nil)
            } footer: {
                Text(plan == nil
                     ? LocalizedStringKey("Elige una distancia, un ritmo o los dos.")
                     : LocalizedStringKey("El anillo marca lo que falta. Con ritmo: verde si vas en ritmo, rojo si vas más lento y amarillo si vas más rápido (± 5 s)."))
            }
        }
        .navigationTitle("Con objetivo")
    }

    private var nearestPace: Double {
        paceOptions.min { abs($0 - paceSeconds) < abs($1 - paceSeconds) } ?? paceSeconds
    }

    private func distanceTitle(_ meters: Double) -> String {
        switch meters {
        case 0: String(localized: "Sin distancia")
        case 21_097.5: String(localized: "Media maratón")
        case 42_195: String(localized: "Maratón")
        default: IntervalPlanFormatter.goal(.distance(meters), unit: .metric)
        }
    }
}
