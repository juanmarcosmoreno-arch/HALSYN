import HalsynCore
import HalsynDesign
import SwiftUI

/// Historial de puntuaciones: tendencia y calendario de las últimas 5 semanas.
/// Cada día abre su desglose.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var scores: [DailyScore]?

    private static let weeks = 5
    private let calendar = Calendar.current

    var body: some View {
        HalsynScreen {
            ModuleHeader(module: .halsa, isDemo: model.isDemo)
                .padding(.top, HalsynSpacing.s)

            if let scores {
                if scores.isEmpty {
                    HalsynEmptyState(
                        systemImage: "calendar",
                        title: "Aún no hay puntuaciones",
                        message: "La puntuación aparece cuando hay datos de al menos el 60 % de las dimensiones. Sigue llevando tu Apple Watch."
                    )
                } else {
                    HalsynCard {
                        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                            HalsynSectionHeader("Evolución", eyebrow: HalsynModule.insikt.brandName)
                            HalsynTrendChart(values: scores.map { DailyValue(day: $0.day, value: Double($0.value)) }, title: "Puntuación", yDomain: 0...100, usualRange: usualRange(scores.map { Double($0.value) }))
                                .frame(height: 230)
                        }
                    }
                    HalsynCard {
                        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                            HalsynSectionHeader("Calendario")
                            calendarGrid(scores)
                            legend
                        }
                    }
                }
            } else {
                HalsynLoadingState()
            }
        }
        .navigationTitle(Text("Historial"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: DailyScore.self) { score in
            ScoreDetailView(score: score)
        }
        .task(id: model.reloadKey) {
            scores = await model.provider.dailyScores(endingOn: .now, days: Self.weeks * 7)
        }
    }

    /// Días de las últimas semanas, alineados al primer día de la semana del usuario.
    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        guard let first = calendar.date(byAdding: .weekOfYear, value: -(Self.weeks - 1), to: thisWeek) else { return [] }
        return (0..<(Self.weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private func calendarGrid(_ scores: [DailyScore]) -> some View {
        let byDay = Dictionary(scores.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { _, last in last })
        let today = calendar.startOfDay(for: .now)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.halsynSecondaryText)
                    .accessibilityHidden(true)
            }
            ForEach(days, id: \.self) { day in
                if let score = byDay[day] {
                    NavigationLink(value: score) {
                        dayCell(day, score: score)
                    }
                    .buttonStyle(.plain)
                } else {
                    dayCell(day, score: nil)
                        .opacity(day > today ? 0.3 : 1)
                }
            }
        }
    }

    private func dayCell(_ day: Date, score: DailyScore?) -> some View {
        VStack(spacing: 2) {
            Text(day, format: .dateTime.day())
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
            ZStack {
                Circle()
                    .fill(score.map { Self.color(for: $0.band) } ?? Color.halsynHairline.opacity(0.4))
                Text(verbatim: score.map { "\($0.value)" } ?? "–")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(score == nil ? Color.halsynSecondaryText : Color(HalsynPalette.darkBackground))
            }
            .frame(width: 34, height: 34)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(score.map { Text(verbatim: "\($0.value) / 100") } ?? Text("Sin datos"))
    }

    private var legend: some View {
        HStack(spacing: HalsynSpacing.s) {
            ForEach([ScoreBand.excellent, .good, .fair, .low], id: \.self) { band in
                HStack(spacing: 4) {
                    Circle().fill(Self.color(for: band)).frame(width: 10, height: 10)
                    Text(LocalizedStringKey(band.title))
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func color(for band: ScoreBand) -> Color {
        switch band {
        case .excellent: Color(HalsynPalette.turquoise)
        case .good: Color(HalsynPalette.mint)
        case .fair: Color(HalsynPalette.cautionDark).opacity(0.7)
        case .low: Color(HalsynPalette.alertDark).opacity(0.7)
        }
    }
}
