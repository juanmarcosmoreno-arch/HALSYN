import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

/// Recuperación del pulso en el reloj: mientras se mide, el pulso, cuánto bajó
/// y la curva; al terminar, la bajada a 1, 2 (y 5) minutos y si guardarla.
struct RecoveryView: View {
    @Environment(WorkoutManager.self) private var workout

    private var meter: RecoveryMeter { workout.recoveryMeter }

    var body: some View {
        switch meter.phase {
        case .measuring:
            MeasuringRecoveryView(meter: meter)
        case let .finished(result):
            RecoveryResultView(meter: meter, result: result)
        case let .failed(message):
            VStack(spacing: 8) {
                Label("No se pudo medir la recuperación", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color(HalsynPalette.cautionDark))
                Text(verbatim: message).font(.caption2)
                Button("Hecho") { meter.close() }
            }
        case nil:
            EmptyView()
        }
    }
}

private struct MeasuringRecoveryView: View {
    let meter: RecoveryMeter

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = meter.elapsed(at: context.date)
            let drop = meter.currentHeartRate.map { meter.endHeartRate - $0 }
            VStack(spacing: 4) {
                Text("RECUPERACIÓN")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Color(HalsynPalette.darkAccent))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: meter.currentHeartRate.map { HalsynFormat.integer($0) } ?? "--")
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("lpm")
                        .font(.caption2)
                        .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                }
                if let drop {
                    Text(verbatim: "\(HalsynFormat.drop(drop)) · \(HalsynFormat.integer(meter.endHeartRate))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Color(HalsynPalette.positiveDark))
                        .accessibilityLabel(Text("Cambio \(HalsynFormat.drop(drop)) desde \(HalsynFormat.integer(meter.endHeartRate))"))
                }
                RecoveryChart(samples: meter.samples, duration: meter.duration)
                    .frame(height: 50)
                ProgressView(value: min(elapsed / meter.duration, 1))
                    .tint(Color(HalsynPalette.darkAccent))
                Text(verbatim: "\(HalsynFormat.duration(elapsed)) / \(HalsynFormat.duration(meter.duration))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                Button("Terminar ya") { meter.stopEarly() }
                    .font(.footnote)
            }
            .padding(.horizontal, 4)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private struct RecoveryResultView: View {
    let meter: RecoveryMeter
    let result: HeartRateRecoveryResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recuperación")
                    .font(.headline)
                    .foregroundStyle(Color(HalsynPalette.darkAccent))
                row("1 min", result.oneMinute)
                row("2 min", result.twoMinutes)
                if result.fiveMinutes != nil {
                    row("5 min", result.fiveMinutes)
                }
                Text("Al terminar: \(HalsynFormat.integer(result.endHeartRate)) lpm")
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                RecoveryChart(samples: result.samples, duration: meter.duration)
                    .frame(height: 60)
                if result.oneMinute == nil {
                    Group {
                        if meter.measuredSeconds < 60 {
                            Text("Se paró antes del minuto: no hay valor para guardar.")
                        } else {
                            Text("No hubo lecturas del pulso cerca del minuto (¿la correa estaba floja?): no hay valor para guardar.")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.cautionDark))
                }
                saveButtons
                Text("Para comparar, recupera siempre igual (por ejemplo, caminando despacio).")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var saveButtons: some View {
        switch meter.saveState {
        case .pending:
            if result.oneMinute != nil {
                Button {
                    Task { await meter.save() }
                } label: {
                    Label("Guardar", systemImage: "heart.text.square")
                        .frame(maxWidth: .infinity)
                }
                .tint(Color(HalsynPalette.darkAccent))
            }
            Button("No guardar") {
                meter.discard()
                meter.close()
            }
        case .saving:
            ProgressView()
        case .saved:
            Label("Guardada (la verás en el iPhone)", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color(HalsynPalette.darkAccent))
            Button("Hecho") { meter.close() }
        case .notSaved:
            Button("Hecho") { meter.close() }
        case let .failed(message):
            Label("No se pudo guardar", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Color(HalsynPalette.cautionDark))
            Text(verbatim: message).font(.caption2)
            Button("Hecho") { meter.close() }
        }
    }

    private func row(_ title: String, _ drop: Double?) -> some View {
        HStack {
            Text(verbatim: title)
                .font(.footnote)
            Spacer()
            Group {
                if let drop {
                    Text("\(HalsynFormat.drop(drop)) lpm")
                } else {
                    Text(verbatim: "—")
                }
            }
            .font(.title3.monospacedDigit().weight(.semibold))
            .foregroundStyle(Color.white)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Curva del pulso durante la recuperación, con marcas a 1 y 2 minutos.
struct RecoveryChart: View {
    let samples: [RecoverySample]
    let duration: TimeInterval

    var body: some View {
        Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                LineMark(x: .value("Segundos", sample.elapsed), y: .value("lpm", sample.bpm))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color(HalsynPalette.alertDark))
            }
            RuleMark(x: .value("1 min", 60))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            if duration > 60 {
                RuleMark(x: .value("2 min", 120))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            }
        }
        .chartXScale(domain: 0...max(duration, 60))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel(Text("Curva del pulso durante la recuperación"))
    }
}
