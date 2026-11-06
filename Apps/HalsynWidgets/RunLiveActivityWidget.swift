import ActivityKit
import HalsynCore
import HalsynDesign
import SwiftUI
import WidgetKit

/// Pantalla bloqueada y Dynamic Island mientras corres con el reloj.
struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            RunLiveLockScreen(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color(HalsynPalette.darkAccent))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RunLiveMetric(title: "DISTANCIA", value: RunLiveText.distance(state), unit: RunLiveText.distanceUnit(state))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RunLiveMetric(title: RunLiveText.speedTitle(state), value: RunLiveText.speed(state), unit: RunLiveText.speedUnit(state), tint: RunLiveText.paceTint(state))
                }
                DynamicIslandExpandedRegion(.center) {
                    RunLiveTimer(state: state)
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let step = state.step {
                            Text(verbatim: step).font(.caption.weight(.bold))
                                .foregroundStyle(Color(HalsynPalette.darkAccent))
                        }
                        Spacer()
                        if let heartRate = state.heartRate {
                            Label {
                                Text(verbatim: "\(Int(heartRate.rounded()))")
                            } icon: {
                                Image(systemName: "heart.fill").foregroundStyle(.red)
                            }
                            .font(.caption.monospacedDigit())
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: RunLiveText.symbol(state))
                    .foregroundStyle(Color(HalsynPalette.darkAccent))
            } compactTrailing: {
                Text(verbatim: RunLiveText.distance(state) + " " + RunLiveText.distanceUnit(state))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(RunLiveText.paceTint(state) ?? .white)
            } minimal: {
                Image(systemName: RunLiveText.symbol(state))
                    .foregroundStyle(Color(HalsynPalette.darkAccent))
            }
        }
    }
}

/// Tarjeta de la pantalla bloqueada: tiempo grande y distancia, ritmo y pulso.
struct RunLiveLockScreen: View {
    let state: RunLiveUpdate
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(verbatim: state.step ?? HalsynModule.spring.brandName)
                        .font(.caption.weight(.bold))
                        .tracking(1)
                } icon: {
                    Image(systemName: RunLiveText.symbol(state))
                }
                .foregroundStyle(Color(HalsynPalette.darkAccent))
                Spacer()
                if state.isPaused {
                    Text("En pausa").font(.caption.weight(.semibold)).foregroundStyle(Color(HalsynPalette.cautionDark))
                } else if isStale {
                    Text("Sin conexión con el reloj").font(.caption2).foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                }
            }
            RunLiveTimer(state: state)
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            HStack(alignment: .bottom) {
                RunLiveMetric(title: "DISTANCIA", value: RunLiveText.distance(state), unit: RunLiveText.distanceUnit(state))
                Spacer()
                RunLiveMetric(title: RunLiveText.speedTitle(state), value: RunLiveText.speed(state), unit: RunLiveText.speedUnit(state), tint: RunLiveText.paceTint(state))
                Spacer()
                RunLiveMetric(title: "PULS", value: state.heartRate.map { "\(Int($0.rounded()))" } ?? "--", unit: String(localized: "lpm"))
            }
            if let target = state.paceTarget {
                Text("Objetivo \(target.formatted(in: state.metric ? .metric : .imperial))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            }
        }
        .padding(16)
    }
}

struct RunLiveTimer: View {
    let state: RunLiveUpdate

    var body: some View {
        if state.isPaused {
            Text(verbatim: HalsynFormat.duration(state.elapsed))
        } else {
            Text(state.timerStart, style: .timer)
        }
    }
}

struct RunLiveMetric: View {
    let title: LocalizedStringKey
    let value: String
    let unit: String
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint ?? .white)
                Text(verbatim: unit)
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            }
        }
    }
}

enum RunLiveText {
    static func symbol(_ state: RunLiveUpdate) -> String {
        switch state.activity {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .ride: "figure.outdoor.cycle"
        }
    }

    private static func unit(_ state: RunLiveUpdate) -> UnitSystem { state.metric ? .metric : .imperial }

    static func distance(_ state: RunLiveUpdate) -> String {
        HalsynFormat.decimal(state.distance / unit(state).metersPerDistanceUnit, fractionDigits: 2)
    }

    static func distanceUnit(_ state: RunLiveUpdate) -> String {
        state.metric ? "km" : "mi"
    }

    static func speedTitle(_ state: RunLiveUpdate) -> LocalizedStringKey {
        state.activity == .ride ? "VELOCIDAD" : "RITMO"
    }

    /// Ritmo actual (o velocidad en bici).
    static func speed(_ state: RunLiveUpdate) -> String {
        guard let pace = state.pace, pace > 0 else { return "--" }
        if state.activity == .ride {
            let perHour = 3600 / pace * 1000 / unit(state).metersPerDistanceUnit
            return HalsynFormat.decimal(perHour, fractionDigits: 1)
        }
        return Pace(secondsPerKilometer: pace).formatted(in: unit(state))
    }

    static func speedUnit(_ state: RunLiveUpdate) -> String {
        if state.activity == .ride { return state.metric ? "km/h" : "mph" }
        return unit(state).paceUnitSymbol
    }

    /// Verde en ritmo, rojo más lento, amarillo más rápido (como el anillo del reloj).
    static func paceTint(_ state: RunLiveUpdate) -> Color? {
        switch state.paceStatus {
        case .slower?: Color(HalsynRGBColor(hex: 0xFF453A))
        case .onPace?: Color(HalsynPalette.darkAccent)
        case .faster?: Color(HalsynPalette.cautionDark)
        case nil: nil
        }
    }
}
