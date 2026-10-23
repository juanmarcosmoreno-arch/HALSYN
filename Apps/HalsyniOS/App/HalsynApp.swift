import HalsynCore
import HalsynDesign
import SwiftUI
import UserNotifications

@main
struct HalsynApp: App {
    @State private var model = AppModel()
    @AppStorage(AppPreferences.appearanceKey) private var appearance: AppearancePreference = .system
    @AppStorage(AppPreferences.onboardingCompletedKey) private var onboardingCompleted = false
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    /// Ajustes de SPRING; al crearse activa WatchConnectivity para enviarlos al reloj.
    @State private var runSettings = RunSettingsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Color.halsynAccent)
                .fullScreenCover(isPresented: Binding(get: { !onboardingCompleted }, set: { onboardingCompleted = !$0 })) {
                    OnboardingView {
                        onboardingCompleted = true
                    }
                    .environment(model)
                    .preferredColorScheme(appearance.colorScheme)
                    .tint(Color.halsynAccent)
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
            }
        }
    }
}
