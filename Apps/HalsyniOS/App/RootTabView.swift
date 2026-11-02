import HalsynCore
import HalsynDesign
import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            HalsaView()
                .tabItem { Label(LocalizedStringKey(HalsynModule.halsa.meaning), systemImage: "heart.text.square") }
                .tag(AppTab.halsa)
            SpringView()
                .tabItem { Label(LocalizedStringKey(HalsynModule.spring.meaning), systemImage: "figure.run") }
                .tag(AppTab.spring)
            CykelView()
                .tabItem { Label(LocalizedStringKey(HalsynModule.cykel.meaning), systemImage: "bicycle") }
                .tag(AppTab.cykel)
            InsiktView()
                .tabItem { Label(LocalizedStringKey(HalsynModule.insikt.meaning), systemImage: "chart.xyaxis.line") }
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
