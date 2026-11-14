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
            FormView()
                .tabItem { Label(LocalizedStringKey(HalsynModule.form.meaning), systemImage: HalsynModule.form.systemImage) }
                .tag(AppTab.form)
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
        // CYKEL ya no es pestaña (va dentro de Correr): si quedó elegida, a Correr.
        .onAppear {
            if model.selectedTab == .cykel { model.selectedTab = .spring }
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppModel())
}
