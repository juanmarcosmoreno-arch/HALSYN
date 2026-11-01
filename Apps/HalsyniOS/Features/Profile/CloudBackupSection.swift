import HalsynDesign
import SwiftUI

/// Perfil › Copia en iCloud: cuándo se hizo la última y restaurar a mano.
struct CloudBackupSection: View {
    @State private var lastBackup = CloudBackup.lastBackup
    @State private var confirmingRestore = false
    @State private var restoredCount: Int?

    var body: some View {
        Section {
            if CloudBackup.isAvailable {
                LabeledContent("Última copia") {
                    if let lastBackup {
                        Text(lastBackup, format: .dateTime.day().month().hour().minute())
                    } else {
                        Text("Todavía no")
                    }
                }
                Button {
                    CloudBackup.backUp()
                    lastBackup = CloudBackup.lastBackup
                } label: {
                    Label("Hacer copia ahora", systemImage: "icloud.and.arrow.up")
                }
                Button {
                    confirmingRestore = true
                } label: {
                    Label("Restaurar desde iCloud", systemImage: "icloud.and.arrow.down")
                }
                if let restoredCount {
                    Text(restoredCount == 0
                         ? LocalizedStringKey("No había nada para restaurar.")
                         : LocalizedStringKey("Restaurado. Cierra la app y vuelve a abrirla para verlo."))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
            } else {
                Label("Inicia sesión en iCloud en Ajustes del iPhone para tener una copia de tus datos.", systemImage: "icloud.slash")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
        } header: {
            Text("Copia en iCloud")
        } footer: {
            Text("Se copian tu plan, tus tests, tus zapatillas (con foto), tus mediciones de recuperación, tus ajustes de carrera, tus metas, tu diario y tu perfil cada vez que sales de la app. En un iPhone nuevo se recuperan solos. Tus entrenamientos, sueño y pulso ya están en Salud.")
        }
        .confirmationDialog("¿Restaurar desde iCloud?", isPresented: $confirmingRestore, titleVisibility: .visible) {
            Button("Restaurar", role: .destructive) {
                restoredCount = CloudBackup.restoreAll()
            }
        } message: {
            Text("Lo de este iPhone se reemplaza por la última copia de iCloud.")
        }
        .onAppear { lastBackup = CloudBackup.lastBackup }
    }
}
