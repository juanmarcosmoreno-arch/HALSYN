import HalsynCore
import HalsynDesign
import SwiftUI

/// SPRING › Ajustes de carrera › Qué dice: elegir qué avisos de voz se oyen.
/// Vale también para la bici (el ritmo pasa a velocidad). Las vibraciones del
/// reloj no cambian.
struct VoiceCuesView: View {
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    private var store: RunSettingsStore { .shared }
    private var cues: VoiceCueSettings { store.settings.cues }

    var body: some View {
        Form {
            Section {
                Toggle("Avisar en las vueltas", isOn: runSetting(\.cues.laps))
                if cues.laps {
                    Picker("Cada", selection: runSetting(\.cues.lapEvery)) {
                        ForEach(VoiceCueSettings.lapEveryOptions, id: \.self) { count in
                            Text(everyTitle(count)).tag(count)
                        }
                    }
                    Toggle("Ritmo de la vuelta", isOn: runSetting(\.cues.lapPace))
                    Toggle("Ritmo medio", isOn: runSetting(\.cues.averagePace))
                    Toggle("Pulso", isOn: runSetting(\.cues.heartRate))
                    Toggle("Tiempo total", isOn: runSetting(\.cues.elapsedTime))
                }
            } header: {
                Text("En las vueltas automáticas")
            } footer: {
                Text("Con la vuelta automática cada kilómetro, «Cada 5» habla en los kilómetros 5, 10, 15… En bici, el ritmo se dice como velocidad.")
            }

            Section {
                Toggle("Series y recuperaciones", isOn: runSetting(\.cues.intervals))
                Toggle("Alertas de ritmo y zona", isOn: runSetting(\.cues.alerts))
            } footer: {
                Text("Las vibraciones del reloj siguen igual aunque apagues un aviso de voz.")
            }

            Section {
                Text(verbatim: CoachPhrases.example(cues: cues, unit: unitSystem))
                    .font(.halsynBody)
                Button {
                    CoachSpeaker.shared.say(CoachPhrases.example(cues: cues, unit: unitSystem))
                } label: {
                    Label("Escuchar el ejemplo", systemImage: "play.circle")
                }
            } header: {
                Text("Así sonará")
            }
        }
        .navigationTitle("Qué dice la voz")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
    }

    private func everyTitle(_ count: Int) -> LocalizedStringKey {
        count == 1 ? "Cada vuelta" : "Cada \(count) vueltas"
    }
}

#Preview {
    NavigationStack { VoiceCuesView() }
}
