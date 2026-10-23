import HalsynCore
import HalsynDesign
import HalsynHealthKit
import SwiftUI
import UIKit

/// Perfil: fuente de datos, permisos, preferencias, módulos y privacidad.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.appearanceKey) private var appearance: AppearancePreference = .system
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @AppStorage(AppPreferences.introKey) private var intro: IntroPreference = .brief
    @AppStorage(AppPreferences.onboardingCompletedKey) private var onboardingCompleted = true
    @Environment(\.openURL) private var openURL
    @State private var isConnecting = false
    @State private var connectionFailed = false

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
                    if model.isDemo {
                        Button {
                            Task {
                                isConnecting = true
                                connectionFailed = !(await model.connectAppleHealth())
                                isConnecting = false
                            }
                        } label: {
                            Label(isConnecting ? LocalizedStringKey("Conectando…") : LocalizedStringKey("Conectar Apple Health"), systemImage: "heart.text.square")
                        }
                        .disabled(isConnecting || !HealthKitAvailability.isHealthDataAvailable)
                    } else {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        } label: {
                            Label("Gestionar permisos", systemImage: "lock.shield")
                        }
                        Button {
                            Task { await model.useDemoData() }
                        } label: {
                            Label("Usar datos demo", systemImage: "testtube.2")
                        }
                    }
                    if connectionFailed {
                        HalsynStatusIndicator(.caution, text: "No se pudo conectar con Apple Health.")
                    }
                } header: {
                    Text("Datos")
                } footer: {
                    if model.isDemo {
                        Text("Ahora HÅLSYN muestra datos sintéticos de demostración. Conecta Apple Health para ver tus datos reales; solo se piden permisos de lectura.")
                    } else {
                        Text("Los permisos de cada tipo de dato se cambian en Ajustes › Salud › Acceso a datos y dispositivos › HÅLSYN. iOS no informa a las apps de qué datos se han denegado.")
                    }
                }

                NightlySummarySection()

                Section("Preferencias") {
                    Picker("Apariencia", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    LanguageRow()
                    Picker("Animación de apertura", selection: $intro) {
                        ForEach(IntroPreference.allCases) { option in
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
                                HStack(spacing: 6) {
                                    Text(verbatim: module.brandName)
                                    Text(verbatim: "·")
                                    Text(LocalizedStringKey(module.meaning))
                                }
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
                    Button("Ver la introducción de nuevo") {
                        onboardingCompleted = false
                    }
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

/// Idioma de la app. iOS gestiona el idioma por app en Ajustes › HÅLSYN ›
/// Idioma; esta fila muestra el actual y abre esa pantalla.
private struct LanguageRow: View {
    @Environment(\.openURL) private var openURL

    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "es"
        return Locale.current.localizedString(forIdentifier: code)?.localizedCapitalized ?? code
    }

    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            LabeledContent("Idioma") {
                HStack(spacing: 4) {
                    Text(verbatim: currentLanguage)
                    Image(systemName: "arrow.up.forward.app")
                        .accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(.halsynPrimaryText)
        .accessibilityHint(Text("Abre los ajustes de la app para cambiar el idioma"))
    }
}

/// Ajustes del resumen nocturno: activar y elegir la hora.
private struct NightlySummarySection: View {
    @AppStorage(AppPreferences.nightlySummaryEnabledKey) private var enabled = false
    @AppStorage(AppPreferences.nightlySummaryTimeKey) private var minutes = AppPreferences.defaultNightlySummaryMinutes
    @State private var notificationsDenied = false

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes = (components.hour ?? 21) * 60 + (components.minute ?? 30)
        }
    }

    var body: some View {
        Section {
            Toggle("Resumen al final del día", isOn: $enabled)
            if enabled {
                DatePicker("Hora", selection: time, displayedComponents: .hourAndMinute)
            }
            if notificationsDenied {
                HalsynStatusIndicator(.caution, text: "Las notificaciones están desactivadas para HÅLSYN en Ajustes.")
            }
        } header: {
            Text("Resumen nocturno")
        } footer: {
            Text("Un aviso diario te invita a ver tu resumen. La notificación no incluye datos de salud.")
        }
        .onChange(of: enabled) { _, _ in Task { await apply() } }
        .onChange(of: minutes) { _, _ in Task { await apply() } }
    }

    private func apply() async {
        guard enabled else {
            NightlySummaryNotifications.cancel()
            return
        }
        let scheduled = await NightlySummaryNotifications.schedule(minutesAfterMidnight: minutes)
        notificationsDenied = !scheduled
        if !scheduled {
            enabled = false
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
