import HalsynCore
import HalsynDesign
import SwiftUI

/// Permisos de Salud y de ubicación del reloj, con lo que hay que elegir para
/// que no se vuelvan a pedir y un historial de cuándo se pidieron.
struct WatchPermissionsView: View {
    @Environment(WorkoutManager.self) private var workout
    @State private var healthPending: Bool?
    @State private var requestingHealth = false
    @State private var log: [PermissionLog.Entry] = []

    var body: some View {
        List {
            Section {
                statusRow(Text(healthStatus), ok: healthPending == false)
                if healthPending == true {
                    Button {
                        Task {
                            requestingHealth = true
                            await workout.requestHealthAuthorization()
                            healthPending = await workout.healthNeedsAuthorization()
                            requestingHealth = false
                            log = PermissionLog.entries
                        }
                    } label: {
                        Label("Permitir Salud", systemImage: "heart.text.square")
                    }
                    .disabled(requestingHealth)
                }
            } header: {
                Text("Salud")
            } footer: {
                Text("Son los mismos permisos en el iPhone y en el reloj. Si aquí no aparece la hoja, abre HÅLSYN en el iPhone y acéptala allí: vale para los dos.")
            }

            Section {
                statusRow(Text(verbatim: PermissionLog.describe(workout.locationAuthorization).capitalizedSentence), ok: workout.locationAuthorization == .authorizedWhenInUse || workout.locationAuthorization == .authorizedAlways)
                if workout.locationAuthorization == .notDetermined {
                    Button {
                        workout.requestLocationIfNeeded()
                    } label: {
                        Label("Permitir ubicación", systemImage: "location")
                    }
                }
            } header: {
                Text("Ubicación")
            } footer: {
                Text("Elige «Permitir al usar la app». «Permitir una vez» se olvida al cerrar la app y el reloj vuelve a preguntar. Para cambiarlo: Ajustes › Privacidad y seguridad › Localización › HÅLSYN.")
            }

            if !log.isEmpty {
                Section {
                    ForEach(log.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.text)
                                .font(.caption2)
                            Text(verbatim: "\(entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())) · build \(entry.build)")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                        }
                    }
                } header: {
                    Text("Historial")
                }
            }
        }
        .navigationTitle(Text("Permisos"))
        .task {
            log = PermissionLog.entries
            healthPending = await workout.healthNeedsAuthorization()
        }
        .onChange(of: workout.locationAuthorization) { _, _ in
            log = PermissionLog.entries
        }
    }

    private var healthStatus: LocalizedStringKey {
        switch healthPending {
        case nil: "Comprobando…"
        case true?: "Falta responder"
        case false?: "Listo"
        }
    }

    private func statusRow(_ text: Text, ok: Bool) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Color(HalsynPalette.positiveDark) : Color(HalsynPalette.cautionDark))
        }
    }
}

private extension String {
    /// "al usar la app" → "Al usar la app".
    var capitalizedSentence: String {
        prefix(1).uppercased() + dropFirst()
    }
}
