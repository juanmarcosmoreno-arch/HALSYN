import HalsynCore
import HalsynDesign
import SwiftUI

/// VILA — descanso: sueño, recuperación, HRV y FC en reposo.
struct VilaView: View {
    @Environment(AppModel.self) private var model
    @State private var recovery: DailyScore?
    @State private var sleep: MetricSeries?
    @State private var hrv: MetricSeries?
    @State private var restingHeartRate: MetricSeries?
    @State private var loaded = false

    var body: some View {
        HalsynScreen {
            ModuleHeader(module: .vila, isDemo: model.isDemo)
                .padding(.top, HalsynSpacing.s)

            if !loaded {
                HalsynLoadingState()
            } else {
                HalsynCard {
                    VStack(spacing: HalsynSpacing.m) {
                        HalsynScoreRing(score: recovery?.value, caption: "Recuperación estimada")
                            .frame(maxWidth: 200)
                        Text("Estimación orientativa del equilibrio entre esfuerzo y descanso. No indica si estás médicamente recuperado.")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                            .multilineTextAlignment(.center)
                        DataOriginFootnote(origin: recovery?.origin, extra: "El motor de recuperación (RecoveryEngine) llega en la Fase 6.")
                    }
                    .frame(maxWidth: .infinity)
                }

                if let sleep {
                    seriesCard(title: "Sueño · 7 días", eyebrow: HalsynLexicon.somn.rawValue, series: sleep, style: .bar) { average in
                        let time = HalsynFormat.hoursAndMinutes(average)
                        HalsynMetric(title: "Media semanal", value: String(localized: "\(time.hours) h \(time.minutes) min"), unit: "")
                    }
                }
                if let hrv {
                    seriesCard(title: "HRV · 7 días", eyebrow: HalsynLexicon.puls.rawValue, series: hrv, style: .line) { average in
                        HalsynMetric(title: "Media semanal", value: HalsynFormat.integer(average), unit: "ms")
                    }
                }
                if let restingHeartRate {
                    seriesCard(title: "FC en reposo · 7 días", eyebrow: HalsynLexicon.puls.rawValue, series: restingHeartRate, style: .line) { average in
                        HalsynMetric(title: "Media semanal", value: HalsynFormat.integer(average), unit: "lpm")
                    }
                }

                HalsynCard {
                    HStack {
                        Text("Fases del sueño, regularidad y relación actividad-descanso")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                        Spacer()
                        PhaseTag(phase: 6)
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: HalsynModule.vila.brandName))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let today = Date.now
            recovery = await model.provider.recoveryScore(on: today)
            sleep = await model.provider.dailySeries(.sleepDuration, days: 7, endingOn: today)
            hrv = await model.provider.dailySeries(.heartRateVariability, days: 7, endingOn: today)
            restingHeartRate = await model.provider.dailySeries(.restingHeartRate, days: 7, endingOn: today)
            loaded = true
        }
    }

    private func seriesCard<Summary: View>(
        title: LocalizedStringKey,
        eyebrow: String,
        series: MetricSeries,
        style: HalsynTrendChart.Style,
        @ViewBuilder summary: (Double) -> Summary
    ) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                Text(verbatim: eyebrow).halsynEyebrowStyle()
                Text(title)
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                HalsynTrendChart(values: series.values, title: series.kind.shortTitle, style: style)
                    .frame(height: 140)
                if let average = series.average {
                    summary(average)
                }
                DataOriginFootnote(origin: series.origin)
            }
        }
    }
}

#Preview {
    NavigationStack { VilaView() }
        .environment(AppModel())
}
