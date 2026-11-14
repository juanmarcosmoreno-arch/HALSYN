import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

enum RouteText {
    static func difference(_ seconds: TimeInterval) -> String {
        (seconds <= 0 ? "−" : "+") + HalsynFormat.duration(abs(seconds))  // nolocalize
    }

    static func name(_ group: RouteGroup, unit: UnitSystem) -> String {
        let distanceText = SessionText.distance(group.distance, unit: unit)
        return group.isLoop ? String(localized: "Circuito de \(distanceText)") : String(localized: "Recorrido de \(distanceText)")
    }
}

/// Tarjeta en el detalle de una carrera que repite un recorrido.
struct RouteComparisonCard: View {
    let workout: WorkoutSummary
    let unitSystem: UnitSystem
    private var store: RouteStore { .shared }

    var body: some View {
        if let group = store.group(for: workout.id), let comparison = store.comparison(for: workout.id) {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    Label("Recorrido repetido", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .halsynEyebrowStyle()
                    let timesText = String(group.members.count)
                    Text("\(RouteText.name(group, unit: unitSystem)) · lo corriste \(timesText) veces")
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    if comparison.hasLongPauses {
                        Label("Tuvo pausas de más de 1 min: el tiempo no se compara.", systemImage: "pause.circle")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynCaution)
                    } else {
                        if let rank = comparison.rank {
                            let rankText = String(rank), totalText = String(comparison.comparableCount)
                            Text("\(rankText).ª de \(totalText) por tiempo en movimiento")
                                .font(.halsynCaption.weight(.semibold))
                        }
                        if let previous = comparison.versusPrevious {
                            let differenceText = RouteText.difference(previous)
                            Text("Frente a la vez anterior: \(differenceText)")
                                .font(.halsynCaption)
                                .foregroundStyle(previous <= 0 ? Color.halsynPositive : Color.halsynSecondaryText)
                        }
                        if let best = comparison.versusBest, best > 0 {
                            let differenceText = RouteText.difference(best)
                            Text("Frente a tu mejor vez: \(differenceText)")
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                    if let heartRate = comparison.heartRateVersusPrevious {
                        let hrText = (heartRate <= 0 ? "−" : "+") + "\(Int(abs(heartRate).rounded())) lpm"  // nolocalize
                        Text("Pulso medio frente a la vez anterior: \(hrText)")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    NavigationLink {
                        RouteDetailView(group: group)
                    } label: {
                        Text("Todas las veces")
                            .font(.halsynCaption.weight(.semibold))
                    }
                }
            }
        }
    }
}

/// Fila de Rendimiento.
struct RoutesAreaLink: View {
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        let groups = RouteStore.shared.groups
        let subtitle: String = {
            guard let top = groups.first else { return String(localized: "Los trayectos que repites, comparados") }
            let countText = String(groups.count), timesText = String(top.members.count)
            return String(localized: "\(countText) recorridos · el más repetido, \(timesText) veces")
        }()
        FormAreaLink(title: "Recorridos", subtitle: subtitle, systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            RoutesView()
        }
    }
}

struct RoutesView: View {
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        let store = RouteStore.shared
        Form {
            if store.groups.isEmpty {
                Text("Todavía no hay recorridos repetidos: aparecen cuando corres al menos dos veces el mismo trayecto al aire libre, en el mismo sentido.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
            ForEach(store.groups) { group in
                NavigationLink {
                    RouteDetailView(group: group)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: RouteText.name(group, unit: unitSystem))
                            .font(.halsynHeadline)
                        let members = group.members.compactMap { store.runs[$0] }
                        let timesText = String(group.members.count)
                        let lastText = members.last.map { $0.start.formatted(date: .abbreviated, time: .omitted) } ?? "—"
                        let bestText = members.map(\.duration).min().map { HalsynFormat.duration($0) } ?? "—"
                        Text("\(timesText) veces · mejor \(bestText) · última \(lastText)")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
            }
            Section {
                Text("Dos carreras son el mismo recorrido si al menos el 85 % de cada una pasa a menos de 30 m de la otra, en el mismo sentido y con inicio y fin a menos de 150 m (en circuitos puede empezar en otro punto). Una distancia parecida no alcanza. Cada carrera se compara con la primera vez del recorrido, para no juntar en cadena trayectos distintos. Los tiempos son en movimiento; si hubo pausas de más de 1 min, esa vez no se compara.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                Text(verbatim: "RouteMatching \(RouteMatching.version)")  // nolocalize
                    .font(.caption2.monospaced())
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .navigationTitle("Recorridos")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
    }
}

/// Todas las veces de un recorrido.
struct RouteDetailView: View {
    let group: RouteGroup
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        let store = RouteStore.shared
        let members = group.members.compactMap { store.runs[$0] }.sorted { $0.start < $1.start }
        let best = members.filter { !(RouteComparisonEngine.compare($0.id, group: group, runs: store.runs)?.hasLongPauses ?? false) }.min { $0.duration < $1.duration }
        Form {
            if members.count >= 2 {
                Section {
                    Chart {
                        ForEach(members) { run in
                            PointMark(x: .value("Fecha", run.start), y: .value("Minutos", run.duration / 60))
                                .foregroundStyle(run.id == best?.id ? Color.halsynHighlight : Color.halsynChart)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 150)
                } footer: {
                    Text("Tiempo en movimiento de cada vez. Más abajo es más rápido.")
                }
            }
            Section("Todas las veces") {
                ForEach(members.reversed()) { run in
                    let comparison = RouteComparisonEngine.compare(run.id, group: group, runs: store.runs)
                    let efficiency = AerobicStore.shared.observations[run.id]?.efficiency
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(run.start, format: .dateTime.day().month(.abbreviated).year())
                                .font(.halsynCaption.weight(.semibold))
                            if run.id == best?.id {
                                Image(systemName: "trophy.fill").foregroundStyle(RunRecordText.medal(1))
                            }
                            Spacer()
                            Text(verbatim: HalsynFormat.duration(run.duration))
                                .font(.halsynCaption.monospacedDigit())
                        }
                        let details = detailText(run, comparison: comparison, efficiency: efficiency)
                        Text(verbatim: details)
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: RouteText.name(group, unit: unitSystem)))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
    }

    /// Ritmo, pulso, eficiencia y avisos de una vez del recorrido.
    private func detailText(_ run: WorkoutSummary, comparison: RouteComparison?, efficiency: Double?) -> String {
        var parts: [String] = []
        if let pace = run.averagePace { parts.append("\(pace.formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol)") }  // nolocalize
        if let heartRate = run.averageHeartRate { parts.append("\(Int(heartRate.rounded())) lpm") }  // nolocalize
        if let efficiency {
            let efficiencyText = HalsynFormat.decimal(efficiency, fractionDigits: 2)
            parts.append(String(localized: "eficiencia \(efficiencyText)"))
        }
        if comparison?.hasLongPauses == true { parts.append(String(localized: "con pausas")) }
        if (comparison?.quality?.coverage ?? 1) < 0.9 { parts.append(String(localized: "coincidencia parcial")) }
        return parts.joined(separator: " · ")
    }
}
