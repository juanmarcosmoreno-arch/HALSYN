import HalsynCore
import HalsynDesign
import SwiftUI

/// Cabecera de pantalla de módulo: nombre sueco, significado y distintivo demo.
struct ModuleHeader: View {
    let module: HalsynModule
    var isDemo: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: module.brandName)
                    .font(.halsynLargeTitle)
                    .tracking(4)
                    .foregroundStyle(.halsynPrimaryText)
                Text(LocalizedStringKey(module.meaning))
                    .halsynEyebrowStyle()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            if isDemo {
                HalsynDemoBadge()
            }
        }
    }
}

/// Nota de origen del dato, obligatoria bajo cualquier valor demo o derivado.
struct DataOriginFootnote: View {
    let origin: DataOrigin?
    var extra: LocalizedStringKey?

    var body: some View {
        if origin != nil || extra != nil {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: origin?.isDemo == true ? "testtube.2" : "info.circle")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let origin {
                        Text(LocalizedStringKey(origin.label))
                    }
                    if let extra {
                        Text(extra)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.halsynSecondaryText)
        }
    }
}

/// Etiqueta "Fase N" para funciones planificadas que aún no existen.
struct PhaseTag: View {
    let phase: Int

    var body: some View {
        Text("Fase \(phase)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.halsynSecondaryText)
            .background(Capsule().strokeBorder(Color.halsynHairline, lineWidth: 1))
            .accessibilityLabel(Text("Planificado para la fase \(phase)"))
    }
}

/// Contenedor de pantalla con scroll y márgenes de HÅLSYN.
struct HalsynScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HalsynSpacing.l) {
                content
            }
            .padding(.horizontal, HalsynSpacing.m)
            .padding(.bottom, HalsynSpacing.xxl)
        }
        .halsynScreenBackground()
    }
}

extension Date {
    /// Fecha larga en el idioma del usuario ("jueves, 23 de octubre").
    var halsynLongDay: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
