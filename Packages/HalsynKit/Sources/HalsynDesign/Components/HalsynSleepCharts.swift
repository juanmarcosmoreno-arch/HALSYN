#if canImport(SwiftUI) && canImport(Charts)
import Charts
import HalsynCore
import SwiftUI

extension SleepSample.Stage {
    /// Rampa ordinal de un solo tono: más profundo, más intenso (validada en ambos modos).
    public var color: Color {
        switch self {
        case .awake: Color(HalsynColorTokens.sleepAwake)
        case .asleepREM: Color(HalsynColorTokens.sleepREM)
        case .asleepCore, .asleepUnspecified: Color(HalsynColorTokens.sleepCore)
        case .asleepDeep: Color(HalsynColorTokens.sleepDeep)
        case .inBed: Color.halsynHairline
        }
    }
}

/// "7 h 32 min" en el idioma del usuario.
public func sleepText(_ seconds: TimeInterval) -> String {
    let time = HalsynFormat.hoursAndMinutes(seconds / 3600)
    return String(localized: "\(time.hours) h \(time.minutes) min", bundle: .main)
}

/// Hipnograma: cada fase en su carril, en el tiempo real de la noche.
/// Al deslizar el dedo, la cabecera dice la fase y la hora.
public struct HalsynHypnogram: View {
    private let night: SleepNight
    @State private var selected: Date?

    public init(night: SleepNight) {
        self.night = night
    }

    private var selectedSegment: SleepSegment? {
        guard let selected else { return nil }
        return night.segments.first { $0.start <= selected && selected < $0.end }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                if let segment = selectedSegment {
                    Circle().fill(segment.stage.color).frame(width: 8, height: 8)
                    Text(LocalizedStringKey(segment.stage.title))
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    Spacer()
                    Text(verbatim: "\(segment.start.formatted(date: .omitted, time: .shortened))–\(segment.end.formatted(date: .omitted, time: .shortened))")
                        .font(.halsynCaption.monospacedDigit())
                        .foregroundStyle(.halsynSecondaryText)
                } else {
                    Text("Desliza para ver cada fase")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                    Spacer()
                }
            }
            .frame(minHeight: 22)
            .animation(.snappy(duration: 0.15), value: selectedSegment)

            Chart {
                ForEach(Array(night.segments.enumerated()), id: \.offset) { _, segment in
                    RectangleMark(
                        xStart: .value("Inicio", segment.start),
                        xEnd: .value("Fin", segment.end),
                        y: .value("Fase", segment.stage.title),
                        height: .ratio(0.72)
                    )
                    .cornerRadius(3)
                    .foregroundStyle(segment.stage.color.opacity(selectedSegment == nil || selectedSegment == segment ? 1 : 0.35))
                }
                if let selected {
                    RuleMark(x: .value("Hora", selected))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.halsynSecondaryText.opacity(0.6))
                }
            }
            .chartYScale(domain: SleepSample.Stage.hypnogramOrder.map(\.title))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let title = value.as(String.self) {
                            Text(LocalizedStringKey(title))
                                .font(.caption2)
                                .foregroundStyle(Color.halsynSecondaryText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.halsynHairline)
                    AxisValueLabel(format: .dateTime.hour())
                        .foregroundStyle(Color.halsynSecondaryText)
                }
            }
            .chartXScale(domain: night.sleepStart...night.sleepEnd)
            .chartXSelection(value: $selected)
            .sensoryFeedback(.selection, trigger: selectedSegment?.stage)
            .frame(height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Hipnograma de la noche"))
        }
    }
}

/// Composición de la noche: una barra con las fases separadas por un hueco de
/// 2 pt y su leyenda con duración y porcentaje.
public struct HalsynSleepComposition: View {
    private let night: SleepNight

    public init(night: SleepNight) {
        self.night = night
    }

    private var parts: [(stage: SleepSample.Stage, seconds: TimeInterval)] {
        SleepSample.Stage.hypnogramOrder.compactMap { stage in
            let seconds = night.stages[stage] ?? 0
            return seconds > 0 ? (stage, seconds) : nil
        }
    }

    public var body: some View {
        let total = max(parts.reduce(0) { $0 + $1.seconds }, 1)
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            GeometryReader { proxy in
                let gaps = CGFloat(max(parts.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(parts, id: \.stage) { part in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(part.stage.color)
                            .frame(width: max(3, (proxy.size.width - gaps) * part.seconds / total))
                    }
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: HalsynSpacing.xs) {
                ForEach(parts, id: \.stage) { part in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(part.stage.color).frame(width: 10, height: 10)
                        Text(LocalizedStringKey(part.stage.title))
                            .foregroundStyle(.halsynPrimaryText)
                        Spacer(minLength: 4)
                        Text(verbatim: "\(sleepText(part.seconds)) · \(Int((part.seconds / total * 100).rounded())) %")
                            .monospacedDigit()
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Horario de cada noche: barra flotante desde que te dormiste hasta que te
/// despertaste. Se ve de un vistazo la duración y la regularidad.
public struct HalsynSleepScheduleChart: View {
    private let nights: [SleepNight]
    private let targetHours: Double?
    @State private var selected: Date?

    public init(nights: [SleepNight], targetHours: Double? = nil) {
        self.nights = nights.sorted { $0.day < $1.day }
        self.targetHours = targetHours
    }

    private var calendar: Calendar { .current }

    /// Minutos desde el mediodía anterior a la noche.
    private func minutes(_ date: Date, night: SleepNight) -> Double {
        date.timeIntervalSince(SleepAggregator.nightWindow(endingOn: night.day, calendar: calendar).start) / 60
    }

    private var domain: ClosedRange<Double> {
        let starts = nights.map { minutes($0.sleepStart, night: $0) }
        let ends = nights.map { minutes($0.sleepEnd, night: $0) }
        let low = ((starts.min() ?? 600) / 60).rounded(.down) * 60
        let high = ((ends.max() ?? 1140) / 60).rounded(.up) * 60
        return low...max(high, low + 120)
    }

    private var selectedNight: SleepNight? {
        guard let selected else { return nil }
        return nights.first { calendar.isDate($0.day, inSameDayAs: selected) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            header
            Chart {
                ForEach(nights) { night in
                    BarMark(
                        x: .value("Noche", night.day, unit: .day),
                        yStart: .value("Se durmió", minutes(night.sleepStart, night: night)),
                        yEnd: .value("Despertó", minutes(night.sleepEnd, night: night)),
                        width: .ratio(0.5)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(Color.halsynChart.opacity(opacity(night)))
                }
            }
            .chartYScale(domain: domain.upperBound...domain.lowerBound)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .stride(by: 120)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.halsynHairline)
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            let time = SleepRegularity.clockTime(minutesFromNoon: minutes)
                            Text(verbatim: String(format: "%02d:%02d", time.hour, time.minute))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.halsynSecondaryText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(nights.count, 7))) { _ in
                    AxisValueLabel(format: nights.count <= 7 ? .dateTime.weekday(.narrow) : .dateTime.day(), centered: true)
                        .foregroundStyle(Color.halsynSecondaryText)
                }
            }
            .chartXSelection(value: $selected)
            .sensoryFeedback(.selection, trigger: selectedNight?.day)
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Horario de sueño por noche"))
            if targetHours != nil {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.halsynChart).frame(width: 10, height: 10)
                    Text("Objetivo cumplido")
                    RoundedRectangle(cornerRadius: 2).fill(Color.halsynChart.opacity(0.4)).frame(width: 10, height: 10)
                        .padding(.leading, HalsynSpacing.s)
                    Text("Por debajo del objetivo")
                }
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
                .accessibilityHidden(true)
            }
        }
    }

    private func opacity(_ night: SleepNight) -> Double {
        if let selectedNight { return night.day == selectedNight.day ? 1 : 0.3 }
        if let targetHours, night.asleep < targetHours * 3600 { return 0.4 }
        return 1
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let night = selectedNight {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: sleepText(night.asleep))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.halsynPrimaryText)
                    Text(night.day, format: .dateTime.weekday(.wide).day().month())
                        .font(.caption)
                        .foregroundStyle(.halsynSecondaryText)
                }
                Spacer()
                Text(verbatim: "\(night.sleepStart.formatted(date: .omitted, time: .shortened)) → \(night.sleepEnd.formatted(date: .omitted, time: .shortened))")
                    .font(.halsynCaption.monospacedDigit())
                    .foregroundStyle(.halsynSecondaryText)
            } else {
                Text("Toca una noche para ver su horario")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .frame(minHeight: 40, alignment: .leading)
        .animation(.snappy(duration: 0.15), value: selectedNight?.day)
    }
}
#endif
