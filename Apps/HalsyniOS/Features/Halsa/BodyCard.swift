import HalsynCore
import HalsynDesign
import SwiftUI

/// KROPP: peso, grasa corporal, masa magra e IMC desde Apple Health
/// (balanzas como la Xiaomi escriben ahí a través de Zepp Life o Mi Fit).
struct BodyCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var weight: MetricReading?
    @State private var fat: MetricReading?
    @State private var lean: MetricReading?
    @State private var series: [DailyValue] = []
    @State private var loaded = false
    private var profile: ReferenceProfileStore { .shared }

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack {
                    HalsynSectionHeader("Cuerpo", eyebrow: HalsynLexicon.kropp.rawValue)
                    Spacer()
                    if model.isDemo { HalsynDemoBadge() }
                }
                if let weight {
                    content(weight)
                } else if loaded {
                    scaleHint
                } else {
                    HalsynLoadingState()
                }
            }
        }
        .task(id: model.reloadKey) {
            let today = Date.now
            weight = await model.provider.latest(.bodyMass, on: today).reading
            fat = await model.provider.latest(.bodyFatPercentage, on: today).reading
            lean = await model.provider.latest(.leanBodyMass, on: today).reading
            series = await model.provider.dailySeries(.bodyMass, days: 90, endingOn: today).values
            loaded = true
        }
    }

    @ViewBuilder
    private func content(_ weight: MetricReading) -> some View {
        NavigationLink(value: HalsaDestination.metric(.bodyMass)) {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    HalsynMetric(title: Calendar.current.isDateInToday(weight.date) ? "Hoy" : "Último registro", value: mass(weight.value), unit: unitSystem.massUnitSymbol)
                    Spacer()
                    if let change = BodyMetrics.monthlyChange(series, endingOn: .now, calendar: .current) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: signed(change))
                                .font(.halsynHeadline.monospacedDigit())
                                .foregroundStyle(.halsynPrimaryText)
                            Text("frente a hace un mes")
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                }
                if !Calendar.current.isDateInToday(weight.date) {
                    Text(weight.date, format: .dateTime.day().month(.wide))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
                if series.count >= 3 {
                    HalsynTrendChart(
                        values: series.map { DailyValue(day: $0.day, value: $0.value / unitSystem.kilogramsPerMassUnit) },
                        title: String(localized: "Peso"),
                        style: .line,
                        unit: unitSystem.massUnitSymbol,
                        format: { HalsynFormat.decimal($0, fractionDigits: 1) }
                    )
                    .frame(height: 140)
                }
            }
        }
        .buttonStyle(.plain)

        HStack(alignment: .top, spacing: HalsynSpacing.s) {
            NavigationLink(value: HalsaDestination.metric(.bodyFatPercentage)) {
                tile("Grasa", fat.map { HalsynFormat.decimal($0.value * 100, fractionDigits: 1) }, "%")
            }
            .buttonStyle(.plain)
            .disabled(fat == nil)
            NavigationLink(value: HalsaDestination.metric(.leanBodyMass)) {
                tile("Masa magra", lean.map { mass($0.value) }, unitSystem.massUnitSymbol)
            }
            .buttonStyle(.plain)
            .disabled(lean == nil)
            bmiTile(weight)
        }
        Text("El peso varía 1–2 kg de un día a otro por agua y comida; la tendencia de semanas es lo que cuenta. La grasa de las balanzas es una estimación.")
            .font(.caption2)
            .foregroundStyle(.halsynSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
        DataOriginFootnote(origin: weight.origin)
    }

    private func tile(_ title: LocalizedStringKey, _ value: String?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.halsynSecondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value ?? "—").font(.halsynHeadline.monospacedDigit())
                if value != nil {
                    Text(verbatim: unit).font(.caption2).foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func bmiTile(_ weight: MetricReading) -> some View {
        if let height = profile.heightCentimeters,
           let bmi = BodyMetrics.bodyMassIndex(weightKilograms: weight.value, heightMeters: height / 100) {
            VStack(alignment: .leading, spacing: 2) {
                Text("IMC").font(.caption2).foregroundStyle(.halsynSecondaryText)
                Text(verbatim: HalsynFormat.decimal(bmi, fractionDigits: 1)).font(.halsynHeadline.monospacedDigit())
                Text("OMS adultos: 18,5–24,9. No distingue músculo de grasa.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button {
                model.selectedTab = .profile
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("IMC").font(.caption2).foregroundStyle(.halsynSecondaryText)
                    Text("Añade tu altura en Perfil").font(.caption2)
                }
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scaleHint: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            Text("Aún no hay peso en Apple Health.")
                .font(.halsynBody)
                .foregroundStyle(.halsynPrimaryText)
            Label {
                Text("¿Tienes una balanza Xiaomi? En la app Zepp Life (o Mi Fit): Perfil › Añadir cuentas › Salud de Apple, y activa peso y grasa corporal. Otras balanzas inteligentes tienen una opción parecida.")
            } icon: {
                Image(systemName: "scalemass")
            }
            .font(.halsynCaption)
            .foregroundStyle(.halsynSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
            if !model.isDemo {
                HealthAccessHint()
            }
        }
    }

    /// "+0,6 kg" / "−0,6 kg".
    private func signed(_ change: Double) -> String {
        let sign = change > 0 ? "+" : (change < 0 ? "−" : "")
        return sign + mass(abs(change)) + " " + unitSystem.massUnitSymbol
    }

    private func mass(_ kilograms: Double) -> String {
        HalsynFormat.decimal(kilograms / unitSystem.kilogramsPerMassUnit, fractionDigits: 1)
    }
}
