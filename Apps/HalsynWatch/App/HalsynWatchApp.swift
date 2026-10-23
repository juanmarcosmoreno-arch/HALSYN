import HalsynCore
import HalsynDesign
import SwiftUI

@main
struct HalsynWatchApp: App {
    @State private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(model)
                .tint(Color(HalsynPalette.darkAccent))
                .task { model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refresh()
            }
        }
    }
}
