import HalsynDesign
import SwiftUI

/// Perfil › Diagnóstico: los informes de cuelgues y cierres que entrega iOS,
/// para compartirlos (traen dónde se trabó la app).
struct DiagnosticsView: View {
    private var store: DiagnosticsStore { .shared }
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                if store.reports.isEmpty {
                    Text("No hay informes. Si la app se traba o se cierra, iOS lo informa la próxima vez que la abres (a veces hasta un día después).")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
                ForEach(store.reports) { report in
                    ShareLink(item: report.url) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.date, format: .dateTime.day().month().hour().minute())
                                    .foregroundStyle(.halsynPrimaryText)
                                Text(summary(report))
                                    .font(.caption2)
                                    .foregroundStyle(.halsynSecondaryText)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            } footer: {
                Text("Toca un informe para compartirlo. No incluye tus datos de salud: solo qué parte de la app estaba funcionando cuando se trabó o se cerró.")
            }
            if !store.reports.isEmpty {
                Section {
                    Button("Borrar informes", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle("Diagnóstico")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Borrar los informes?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { store.deleteAll() }
        }
    }

    private func summary(_ report: DiagnosticsStore.Report) -> LocalizedStringKey {
        "Cierres: \(report.crashes) · Cuelgues: \(report.hangs) · Otros: \(report.other)"
    }
}
