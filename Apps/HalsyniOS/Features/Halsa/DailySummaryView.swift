import HalsynCore
import HalsynDesign
import SwiftUI

/// Frases del resumen del día (solo con datos disponibles).
struct DailySummaryList: View {
    let statements: [SummaryStatement]

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            ForEach(statements, id: \.self) { statement in
                HStack(alignment: .firstTextBaseline, spacing: HalsynSpacing.s) {
                    Image(systemName: ScoreTexts.statementIcon(statement))
                        .foregroundStyle(.halsynAccent)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    ScoreTexts.statement(statement)
                        .font(.halsynBody)
                        .foregroundStyle(.halsynPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Resumen del día a pantalla completa (se abre desde la notificación nocturna).
struct DailySummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var statements: [SummaryStatement]?

    var body: some View {
        NavigationStack {
            HalsynScreen {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: HalsynModule.halsa.brandName).halsynEyebrowStyle()
                    Text("Resumen del día")
                        .font(.halsynLargeTitle)
                        .foregroundStyle(.halsynPrimaryText)
                    Text(verbatim: Date.now.halsynLongDay.capitalized)
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
                .padding(.top, HalsynSpacing.s)

                if let statements {
                    HalsynCard {
                        if statements.isEmpty {
                            Text("Todavía no hay datos suficientes de hoy para un resumen.")
                                .font(.halsynBody)
                                .foregroundStyle(.halsynSecondaryText)
                        } else {
                            DailySummaryList(statements: statements)
                        }
                    }
                    if model.isDemo { HalsynDemoBadge() }
                    Text("Resumen orientativo basado solo en tus datos disponibles. No es una valoración médica.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                } else {
                    HalsynLoadingState()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task(id: model.reloadKey) {
                statements = await model.provider.dailySummary(on: .now, calendar: .current)
            }
        }
    }
}
