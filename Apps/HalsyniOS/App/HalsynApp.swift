import HalsynCore
import HalsynDesign
import SwiftUI
import UIKit
import UserNotifications

@main
struct HalsynApp: App {
    /// Antes que nada (los datos se leen al crear cada almacén): en un iPhone
    /// nuevo o con la app reinstalada, trae de iCloud lo que falta.
    private let restoredFromCloud = CloudBackup.restoreMissing()
    /// Completa en el iPhone los permisos de Salud que pide el reloj.
    @UIApplicationDelegateAdaptor(HalsynAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @AppStorage(AppPreferences.appearanceKey) private var appearance: AppearancePreference = .system
    @AppStorage(AppPreferences.onboardingCompletedKey) private var onboardingCompleted = false
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    /// Ajustes de SPRING; al crearse activa WatchConnectivity para enviarlos al reloj.
    @State private var runSettings = RunSettingsStore.shared
    @AppStorage(AppPreferences.introKey) private var intro: IntroPreference = .brief
    /// Tema de colores (Perfil › Colores).
    @AppStorage(HalsynTheme.storageKey) private var themeID = HalsynTheme.halsyn.id
    /// La intro solo se muestra en el arranque en frío, no al volver a primer plano.
    @State private var showsIntro = !UIAccessibility.isReduceMotionEnabled
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        HalsynTheme.current = HalsynTheme.named(UserDefaults.standard.string(forKey: HalsynTheme.storageKey))
        // Enfermedad o lesión registradas: la recuperación las tiene en cuenta desde el inicio.
        IntensityContext.updateRecoveryContext()
    }

    /// La primera vez siempre se ve completa; después, según la preferencia.
    private var resolvedIntro: IntroPreference? {
        if !onboardingCompleted { return .full }
        return intro == .off ? nil : intro
    }

    var body: some Scene {
        WindowGroup {
            // El tema se fija antes de dibujar; cambiarlo rehace las pantallas.
            let _ = HalsynTheme.current = HalsynTheme.named(themeID)
            RootTabView()
                .id(themeID)
                .environment(model)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Color.halsynAccent)
                .overlay {
                    if showsIntro, let preference = resolvedIntro {
                        IntroVideoView(preference: preference) {
                            withAnimation(.easeOut(duration: 0.45)) { showsIntro = false }
                        }
                        .preferredColorScheme(appearance.colorScheme)
                        .transition(.opacity)
                        .zIndex(1)
                    }
                }
                // La introducción espera a que termine la animación de apertura.
                .fullScreenCover(isPresented: Binding(get: { !onboardingCompleted && !(showsIntro && resolvedIntro != nil) }, set: { onboardingCompleted = !$0 })) {
                    OnboardingView {
                        onboardingCompleted = true
                    }
                    .environment(model)
                    .preferredColorScheme(appearance.colorScheme)
                    .tint(Color.halsynAccent)
                }
                // Enlaces de los widgets: halsyn://halsa, halsyn://spring, halsyn://insikt…
                .onOpenURL { url in
                    switch url.host {
                    case "spring": model.selectedTab = .spring
                    case "cykel": model.openCykel()
                    case "insikt": model.selectedTab = .insikt
                    case "profile": model.selectedTab = .profile
                    default: model.selectedTab = .halsa
                    }
                }
                .task {
                    NotificationRouter.shared.onOpenDailySummary = { [model] in
                        model.selectedTab = .halsa
                        model.isShowingDailySummary = true
                    }
                    await model.start()
                }
        }
        .onChange(of: unitSystem, initial: true) { _, unit in
            // El reloj muestra las mismas unidades que el iPhone.
            runSettings.update { $0.unitSystem = unit }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refresh()
                LiveRunActivity.shared.appBecameActive()
            } else if phase == .background {
                CloudBackup.backUp()
            }
        }
    }
}
