import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

/// "Tus estadísticas": totales de la semana, el mes o el año, comparación con
/// el periodo anterior a la misma altura, distancia por semana o por mes y
/// récords. En SPRING solo carreras (no caminatas); en CYKEL solo bici, con
/// velocidad en lugar de ritmo y el desnivel.
struct RunningStatsCard: View {
    let workouts: [WorkoutSummary]
    var sport: WorkoutSport = .running
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @AppStorage("halsyn.spring.statsPeriod") private var runPeriod: StatsPeriod = .week
    @AppStorage("halsyn.cykel.statsPeriod") private var ridePeriod: StatsPeriod = .week

    private let columns = [GridItem(.flexible(), spacing: HalsynSpacing.s), GridItem(.flexible(), spacing: HalsynSpacing.s)]

    private var isCycling: Bool { sport == .cycling }

    private var period: Binding<StatsPeriod> {
        isCycling ? $ridePeriod : $runPeriod
    }

    var body: some View {
        let stats = RunningStatsBuilder.build(runs: workouts, period: period.wrappedValue, today: .now, calendar: .current, sport: sport)
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Tus estadísticas", eyebrow: HalsynLexicon.rorelse.rawValue)
                Picker("Periodo", selection: period) {
                    ForEach(StatsPeriod.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: columns, alignment: .leading, spacing: HalsynSpacing.m) {
                    HalsynMetric(title: "Distancia", value: HalsynFormat.distance(meters: stats.current.distance, unit: unitSystem), unit: unitSystem.distanceUnitSymbol)
                    HalsynMetric(title: isCycling ? "Salidas" : "Carreras", value: String(stats.current.count), unit: "")
                    HalsynMetric(title: "Tiempo", value: stats.current.duration > 0 ? sleepText(stats.current.duration) : "0", unit: "")
                    if isCycling {
                        HalsynMetric(title: "Velocidad media", value: stats.current.averageSpeed?.formatted(in: unitSystem), unit: unitSystem.speedUnitSymbol)
                        if let gain = stats.current.elevationGain {
                            HalsynMetric(title: "Desnivel", value: HalsynFormat.integer(gain), unit: "m")
                        }
                        if let power = stats.current.averagePower {
                            HalsynMetric(title: "Potencia media", value: HalsynFormat.integer(power), unit: "W")
                        }
                    } else {
                        HalsynMetric(title: "Ritmo medio", value: stats.current.averagePace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol)
                    }
                    if let heartRate = stats.current.averageHeartRate {
                        HalsynMetric(title: "FC media", value: HalsynFormat.integer(heartRate), unit: String(localized: "lpm"))
                    }
                }

                Text(comparison(stats))
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)

                chart(stats)

                if stats.records.longest != nil || stats.records.fastest != nil {
                    Divider().overlay(Color.halsynHairline)
                    Text("Récords")
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    if let longest = stats.records.longest {
                        recordRow(isCycling ? "Salida más larga" : "Carrera más larga", value: SessionText.distance(longest.distanceMeters ?? 0, unit: unitSystem), workout: longest)
                    }
                    if isCycling {
                        if let fastest = stats.records.fastest, let speed = fastest.averageSpeed {
                            recordRow("Más rápida (20 km o más)", value: speed.formatted(in: unitSystem) + " " + unitSystem.speedUnitSymbol, workout: fastest)
                        }
                        if let climb = stats.records.mostClimbing, let gain = climb.elevationGain {
                            recordRow("Más desnivel", value: HalsynFormat.integer(gain) + " m", workout: climb)
                        }
                    } else if let fastest = stats.records.fastest, let pace = fastest.averagePace {
                        recordRow("Mejor ritmo (5 km o más)", value: pace.formatted(in: unitSystem) + " " + unitSystem.paceUnitSymbol, workout: fastest)
                    }
                    if let week = stats.records.biggestWeek {
                        HStack {
                            Text("Semana con más distancia")
                                .font(.halsynCaption)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(verbatim: SessionText.distance(week.distance, unit: unitSystem))
                                    .font(.halsynCaption.monospacedDigit().weight(.semibold))
                                Text(week.start, format: .dateTime.day().month(.abbreviated).year())
                                    .font(.caption2)
                                    .foregroundStyle(.halsynSecondaryText)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text(isCycling ? LocalizedStringKey("Entre las salidas en bici guardadas en Salud que carga HÅLSYN.") : LocalizedStringKey("Entre las carreras guardadas en Salud que carga HÅLSYN."))
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
    }

    private func comparison(_ stats: RunningStats) -> LocalizedStringKey {
        let before = SessionText.distance(stats.previousToDate.distance, unit: unitSystem)
        switch stats.period {
        case .week: return "A esta altura de la semana pasada: \(before)"
        case .month: return "A esta altura del mes pasado: \(before)"
        case .year: return "A esta altura del año pasado: \(before)"
        }
    }

    private func chart(_ stats: RunningStats) -> some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            Chart(stats.buckets) { bucket in
                BarMark(
                    x: .value("Periodo", bucket.start, unit: stats.period == .year ? .month : .weekOfYear),
                    y: .value("Distancia", bucket.distance / unitSystem.metersPerDistanceUnit)
                )
                .cornerRadius(3)
                .foregroundStyle(bucket.isCurrent ? Color.halsynHighlight : Color.halsynChart.opacity(0.8))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: stats.period == .year ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Color.halsynHairline)
                    AxisValueLabel()
                }
            }
            .frame(height: 140)
            .accessibilityLabel(Text(stats.period == .year ? LocalizedStringKey("Distancia por mes") : LocalizedStringKey("Distancia por semana")))
            Text(stats.period == .year ? LocalizedStringKey("Distancia por mes · últimos 12 meses") : LocalizedStringKey("Distancia por semana · últimas 12 semanas"))
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    private func recordRow(_ title: LocalizedStringKey, value: String, workout: WorkoutSummary) -> some View {
        NavigationLink(value: workout) {
            HStack {
                Text(title)
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynPrimaryText)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: value)
                        .font(.halsynCaption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.halsynPrimaryText)
                    Text(workout.start, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
