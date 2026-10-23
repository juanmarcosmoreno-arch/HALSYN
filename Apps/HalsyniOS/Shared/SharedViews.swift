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
                        originText(origin)
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

/// Texto localizado del origen (no se usa `DataOrigin.label`, que interpola
/// valores y no puede traducirse como clave).
private func originText(_ origin: DataOrigin) -> Text {
    switch origin {
    case .demo:
        Text("Datos demo")
    case .healthKit(let source?):
        Text("Apple Health · \(source)")
    case .healthKit(nil):
        Text(verbatim: "Apple Health")
    case .derived(let engine):
        Text("Calculado por \(engine)")
    }
}

/// Ayuda cuando faltan datos reales. HealthKit no revela si el usuario denegó
/// la lectura de un tipo, así que se sugiere revisar los permisos sin afirmarlo.
struct HealthAccessHint: View {
    var body: some View {
        HStack(alignment: .top, spacing: HalsynSpacing.s) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.halsynAccentText)
                .accessibilityHidden(true)
            Text("¿Faltan datos? Comprueba en Ajustes › Salud › Acceso a datos y dispositivos › HÅLSYN qué datos compartes, y que llevas el Apple Watch.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        }
        .padding(HalsynSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HalsynRadius.small, style: .continuous).fill(Color.halsynAccentSoft.opacity(0.25)))
        .accessibilityElement(children: .combine)
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
