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
                Picker(selection: runSetting(\.rideLapUnits)) {
                    ForEach(RunSettings.rideAutoLapUnitOptions, id: \.self) { count in
                        Text(autoLapTitle(count)).tag(count)
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
                Toggle(isOn: runSetting(\.usesOwnRideZones)) {
                    Label("Zonas propias para la bici", systemImage: "heart")
                }
                if settings.usesOwnRideZones {
                    NavigationLink {
                        ZoneSettingsView(sport: .cycling)
                    } label: {
                        LabeledContent {
                            Text(zonesSummary)
                        } label: {
                            Label("Zonas de bici", systemImage: "bicycle")
                        }
                    }
                }
            } header: {
                Text("Zonas cardíacas")
            } footer: {
                Text(settings.usesOwnRideZones
                     ? LocalizedStringKey("El reloj y el detalle de cada salida usan estas zonas. Parten de una copia de las de SPRING (sin la FC máxima registrada corriendo): pon la de bici, que suele ser algo más baja.")
                     : LocalizedStringKey("Ahora se usan las zonas de SPRING. Los umbrales de pulso no se trasladan bien de correr a pedalear, así que conviene tener zonas propias si entrenas en bici."))
            }

            Section {
                Text("Los avisos de voz y dónde suenan son los mismos que en SPRING.")
                    .font(.halsynCaption)
                NavigationLink {
                    RunSettingsView()
                } label: {
                    Label("Ajustes de carrera", systemImage: "figure.run")
                }
            } header: {
                Text("Voz")
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

    private var zonesSummary: LocalizedStringKey {
        guard let max = settings.cyclingZones.zones.last?.upperBound else { return "Sin configurar" }
        return "FC máx. \(Int(max)) lpm"
    }

    private func autoLapTitle(_ count: Int) -> LocalizedStringKey {
        guard count > 0 else { return "Desactivada" }
        return settings.unitSystem == .imperial ? "Cada \(count) mi" : "Cada \(count) km"
    }
}

#Preview {
    NavigationStack { RideSettingsView() }
        .environment(AppModel())
}
