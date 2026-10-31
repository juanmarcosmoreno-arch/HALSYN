import HalsynCore
import HalsynDesign
import SwiftUI

/// Calentamiento antes del entrenamiento: un anillo que se va gastando con el
/// tiempo (o la distancia) que falta. No se graba; al terminar empieza la sesión.
struct WarmupView: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var warmup: WarmupSession { workout.warmup }
    private var unitSystem: UnitSystem { RunSettingsStore.shared.settings.unitSystem }
    private let tint = Color(HalsynPalette.cautionDark)

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 1 : 0.5)) { context in
            VStack(spacing: 4) {
                HStack {
                    Text("CALENTAR")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(tint)
                    Spacer()
                    Text(verbatim: warmup.heartRate.map { "\(HalsynFormat.integer($0)) ♥" } ?? "--")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.white)
                }
                dial(at: context.date)
                Text("No se graba: el entrenamiento empieza al terminar.")
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                HStack {
                    Button("Cancelar", role: .cancel) { warmup.cancel() }
                    Button("Empezar ya") { warmup.finish() }
                        .tint(Color(HalsynPalette.darkAccent))
                }
                .font(.footnote)
            }
            .padding(.horizontal, 4)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func dial(at date: Date) -> some View {
        let remaining = warmup.remainingFraction(at: date)
        return ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: 9)
            Circle()
                .trim(from: 0, to: remaining ?? 1)
                .stroke(tint.opacity(remaining == nil ? 0.5 : 1), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: remaining)
            VStack(spacing: 0) {
                Text(remaining == nil ? LocalizedStringKey("TID") : LocalizedStringKey("QUEDAN"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(verbatim: centerValue(at: date))
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Color.white)
                if case .distance = warmup.goal {
                    Text(verbatim: unitSystem.distanceUnitSymbol)
                        .font(.caption2)
                        .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                }
            }
            .padding(.horizontal, 16)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }

    private func centerValue(at date: Date) -> String {
        let elapsed = warmup.elapsed(at: date)
        switch warmup.goal {
        case let .time(seconds):
            return HalsynFormat.duration(max(0, seconds - elapsed))
        case let .distance(meters):
            return HalsynFormat.distance(meters: max(0, meters - warmup.distance), unit: unitSystem)
        default:
            return HalsynFormat.duration(elapsed)
        }
    }
}
