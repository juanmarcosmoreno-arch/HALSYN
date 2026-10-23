import HalsynCore
import HalsynDesign
import SwiftUI
import UserNotifications

/// Qué tipo de día es hoy: recuperación + señales que se salen de lo habitual.
struct TodayGuidanceCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var recovery: Int?
    @State private var signals: UnusualSignals?
    @State private var loaded = false

    private var guidance: TrainingGuidance { ReadinessEngine.guidance(recovery: recovery, signals: signals) }

    var body: some View {
        VStack(spacing: 0) {
            if loaded {
                card
            }
        }
        .task(id: model.reloadKey) { await load() }
    }

    private var card: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HStack(alignment: .center, spacing: HalsynSpacing.m) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .frame(width: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hoy")
                            .halsynEyebrowStyle()
                        Text(title)
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if let recovery {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(verbatim: "\(recovery)")
                                .font(.halsynMetricValue)
                            Text(verbatim: HalsynModule.vila.brandName)
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if let signals, !signals.signals.isEmpty {
                    ForEach(signals.signals) { signal in
                        Label {
                            Text(verbatim: describe(signal))
                        } icon: {
                            Image(systemName: signal.metric.systemImage)
                        }
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynCaution)
                    }
                    if signals.isNotable {
                        Text("Varias señales se apartan a la vez de tu rango habitual. Suele pasar con cansancio acumulado, alcohol, estrés, calor o al empezar un resfriado. No es un diagnóstico: si te encuentras mal, consulta a un profesional.")
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: LocalizedStringKey {
        switch guidance {
        case .push: "Buen día para un entreno exigente"
        case .steady: "Día para un entreno moderado"
        case .easy: "Mejor algo suave hoy"
        case .rest: "Hoy, prioriza descansar"
        case .unknown: "Aún no hay datos de recuperación de hoy"
        }
    }

    private var detail: LocalizedStringKey {
        switch guidance {
        case .push: "Tu recuperación es buena y no hay señales fuera de lo normal. Escucha a tu cuerpo igualmente."
        case .steady: "Puedes entrenar con normalidad; deja lo más intenso para otro día si notas cansancio."
        case .easy: "Un rodaje suave, caminar o movilidad te ayudarán más que un entreno duro."
        case .rest: "Descanso, sueño y agua. Si mañana las señales vuelven a tu rango, retoma poco a poco."
        case .unknown: "Se calcula con tu sueño, tu HRV y tu FC en reposo de esta noche."
        }
    }

    private var icon: String {
        switch guidance {
        case .push: "bolt.fill"
        case .steady: "figure.run"
        case .easy: "figure.walk"
        case .rest: "bed.double.fill"
        case .unknown: "clock"
        }
    }

    private var tint: Color {
        switch guidance {
        case .push: .halsynPositive
        case .steady: .halsynAccentText
        case .easy, .rest: .halsynHighlight
        case .unknown: .halsynSecondaryText
        }
    }

    /// "FC en reposo: 59 lpm (habitual 52)".
    private func describe(_ signal: BodySignal) -> String {
        let value = HalsynFormat.metricValue(signal.value, kind: signal.metric, unit: unitSystem)
        let usual = HalsynFormat.metricValue(signal.baselineMean, kind: signal.metric, unit: unitSystem)
        let unit = String(localized: String.LocalizationValue(HalsynFormat.unitSymbol(for: signal.metric, unit: unitSystem)))
        let name = String(localized: String.LocalizationValue(signal.metric.title))
        return String(localized: "\(name): \(value) \(unit) (habitual \(usual))")
    }

    private func load() async {
        let today = Date.now
        recovery = await model.provider.recoveryEstimates(endingOn: today, days: 1).last { Calendar.current.isDateInToday($0.day) }?.value
        signals = await model.provider.unusualSignals(on: today, calendar: .current)
        loaded = true
    }
}

/// Aviso por la mañana. El texto no incluye datos de salud.
enum MorningReadinessNotifications {
    static let identifier = "halsyn.morningReadiness"

    static func schedule(minutesAfterMidnight minutes: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = "HÅLSYN"
        content.body = String(localized: "Tu preparación de hoy está lista.")
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
            return true
        } catch {
            return false
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
