import HalsynCore
import HalsynDesign
import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.cykelTabKey) private var showsCykelTab = false

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            HalsaView()
                .tabItem { Label(LocalizedStringKey(HalsynModule.halsa.meaning), systemImage: "heart.text.square") }
                .tag(AppTab.halsa)
            SpringView()
                .tabItem { Label(LocalizedStringKey(HalsynModule.spring.meaning), systemImage: "figure.run") }
                .tag(AppTab.spring)
            if showsCykelTab {
                CykelView()
                    .tabItem { Label(LocalizedStringKey(HalsynModule.cykel.meaning), systemImage: "bicycle") }
                    .tag(AppTab.cykel)
            }
            InsiktView()
                .tabItem { Label(LocalizedStringKey(HalsynModule.insikt.meaning), systemImage: "chart.xyaxis.line") }
                .tag(AppTab.insikt)
            ProfileView()
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .sheet(isPresented: $model.isShowingCykel) {
            CykelView()
                .environment(model)
                .presentationDragIndicator(.visible)
        }
        // Si se oculta la pestaña de CYKEL estando en ella, se vuelve a HÄLSA.
        .onChange(of: showsCykelTab) { _, shows in
            if !shows && model.selectedTab == .cykel { model.selectedTab = .halsa }
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppModel())
}
