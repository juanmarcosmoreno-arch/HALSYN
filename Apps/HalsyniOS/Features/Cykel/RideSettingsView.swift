import HalsynCore
import HalsynDesign
import SwiftUI

/// CYKEL › Ajustes de bici. Se guardan al momento y se envían al Apple Watch
/// junto con los de SPRING (voz y zonas cardíacas son comunes).
struct RideSettingsView: View {
    private var store: RunSettingsStore { .shared }
    private var settings: RunSettings { store.settings }
    @State private var editingFTP = false

    var body: some View {
        Form {
            Section {
                Picker(selection: runSetting(\.rideAutoLapDistance)) {
                    ForEach(settings.rideAutoLapOptions, id: \.self) { option in
                        Text(autoLapTitle(option)).tag(option)
                    }
                } label: {
                    Label("Vuelta automática", systemImage: "flag")
                }
            } footer: {
                Text("En cada vuelta el reloj vibra y, con los avisos de voz activados, dice la distancia, la velocidad de ese tramo y el pulso.")
            }

            Section {
                LabeledContent {
                    Text(verbatim: settings.validFunctionalThresholdPower.map { "\(HalsynFormat.integer($0)) W" } ?? "—")
                } label: {
                    Label("Tu FTP", systemImage: "bolt")
                }
                Button(settings.functionalThresholdPower == nil ? LocalizedStringKey("Escribir mi FTP") : LocalizedStringKey("Cambiar mi FTP")) {
                    editingFTP = true
                }
            } header: {
                Text("Potencia")
            } footer: {
                Text("Con tu FTP, el reloj muestra en qué zona de potencia vas (Z1–Z7) y el iPhone calcula la intensidad y la carga de cada salida.")
            }

            Section {
                Text("Los avisos de voz, dónde suenan y las zonas cardíacas son los mismos que en SPRING.")
                    .font(.halsynCaption)
                NavigationLink {
                    RunSettingsView()
                } label: {
                    Label("Ajustes de carrera", systemImage: "figure.run")
                }
            } header: {
                Text("Voz y zonas")
            }

            Section {
                Text("Medidor de potencia, sensor de cadencia o de velocidad: emparéjalos en el reloj, en Ajustes › Bluetooth. HÅLSYN los usa durante la salida y sus datos quedan en Apple Health. Sin ellos, potencia y cadencia se muestran vacías: no se estiman.")
                    .font(.halsynCaption)
            } header: {
                Text("Sensores")
            }
        }
        .navigationTitle("Ajustes de bici")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
        .sheet(isPresented: $editingFTP) {
            FTPEditorSheet(initial: settings.validFunctionalThresholdPower ?? FTPStore.shared.resolved(manual: nil)?.watts)
                .presentationDetents([.medium])
        }
    }

    private func autoLapTitle(_ distance: Double?) -> LocalizedStringKey {
        guard let distance else { return "Desactivada" }
        let count = Int((distance / settings.unitSystem.metersPerDistanceUnit).rounded())
        return settings.unitSystem == .imperial ? "Cada \(count) mi" : "Cada \(count) km"
    }
}

#Preview {
    NavigationStack { RideSettingsView() }
        .environment(AppModel())
}
