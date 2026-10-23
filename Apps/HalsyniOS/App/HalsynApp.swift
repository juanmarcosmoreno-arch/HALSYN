import HalsynCore
import HalsynDesign
import SwiftUI

@main
struct HalsynApp: App {
    @State private var model = AppModel()
    @AppStorage(AppPreferences.appearanceKey) private var appearance: AppearancePreference = .system

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Color.halsynAccent)
        }
    }
}
