import HalsynCore
import HalsynDesign
import HalsynHealthKit
import SwiftUI

/// Perfil: fuente de datos, permisos, preferencias, módulos y privacidad.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.appearanceKey) private var appearance: AppearancePreference = .system
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        HalsynLogo(.vertical, height: 72)
                            .padding(.vertical, HalsynSpacing.m)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    LabeledContent("Fuente activa") {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey(model.dataMode.title))
                            if model.isDemo { HalsynDemoBadge() }
                        }
                    }
                    LabeledContent("HealthKit en este dispositivo") {
                        HalsynStatusIndicator(
                            HealthKitAvailability.isHealthDataAvailable ? .positive : .caution,
                            text: HealthKitAvailability.isHealthDataAvailable ? "Disponible" : "No disponible"
                        )
                    }
                    HStack {
                        Label("Conectar Apple Health", systemImage: "heart.text.square")
                            .foregroundStyle(.halsynSecondaryText)
                        Spacer()
                        PhaseTag(phase: 2)
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("Datos")
                } footer: {
                    Text("Ahora mismo HÅLSYN muestra datos sintéticos de demostración. La lectura real de Apple Health, con permisos granulares, se implementa en la Fase 2.")
                }

                Section("Preferencias") {
                    Picker("Apariencia", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker("Unidades", selection: $unitSystem) {
                        ForEach(UnitSystem.allCases) { system in
                            Text(LocalizedStringKey(system.title)).tag(system)
                        }
                    }
                }

                Section("Módulos") {
                    ForEach(HalsynModule.allCases) { module in
                        HStack(alignment: .top, spacing: HalsynSpacing.m) {
                            Image(systemName: module.systemImage)
                                .foregroundStyle(.halsynAccent)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "\(module.brandName) · \(module.meaning)")
                                    .font(.halsynHeadline)
                                Text(LocalizedStringKey(module.summary))
                                    .font(.halsynCaption)
                                    .foregroundStyle(.halsynSecondaryText)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    NavigationLink("Vocabulario sueco") {
                        LexiconView()
                    }
                }

                Section {
                    Label("Local-first: tus datos se procesan en el dispositivo.", systemImage: "iphone")
                    Label("Sin publicidad ni venta de datos.", systemImage: "hand.raised")
                    Label("Sin envío de métricas a servicios de IA.", systemImage: "lock")
                } header: {
                    Text("Privacidad")
                } footer: {
                    Text("HÅLSYN ofrece estimaciones de bienestar y rendimiento. No es un dispositivo médico, no diagnostica enfermedades y no sustituye la valoración de un profesional sanitario.")
                }

                Section("Desarrollo") {
                    NavigationLink("Galería del design system") {
                        DesignSystemGalleryView()
                    }
                    LabeledContent("Versión", value: Bundle.main.halsynVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .halsynScreenBackground()
            .navigationTitle("Perfil")
        }
    }
}

private struct LexiconView: View {
    var body: some View {
        List(HalsynLexicon.allCases, id: \.self) { word in
            LabeledContent {
                Text(LocalizedStringKey(word.meaning))
            } label: {
                Text(verbatim: word.rawValue).font(.halsynHeadline).tracking(1.5)
            }
        }
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
        .navigationTitle("Vocabulario")
    }
}

extension Bundle {
    var halsynVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

#Preview {
    ProfileView()
        .environment(AppModel())
}
