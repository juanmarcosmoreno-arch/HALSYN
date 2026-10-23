import HalsynCore
import HalsynDesign
import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            HalsaView()
                .tabItem { Label(HalsynModule.halsa.brandName, systemImage: "heart.text.square") }
                .tag(AppTab.halsa)
            SpringView()
                .tabItem { Label(HalsynModule.spring.brandName, systemImage: "figure.run") }
                .tag(AppTab.spring)
            InsiktView()
                .tabItem { Label(HalsynModule.insikt.brandName, systemImage: "chart.xyaxis.line") }
                .tag(AppTab.insikt)
            ProfileView()
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppModel())
}
