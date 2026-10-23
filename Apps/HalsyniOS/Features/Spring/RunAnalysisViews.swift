import Charts
import HalsynCore
import HalsynDesign
import MapKit
import SwiftUI

/// Qué colorea el mapa y el perfil de la carrera.
enum RunColoring: String, CaseIterable, Identifiable {
    case pace
    case heartRate

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pace: "Ritmo"
        case .heartRate: "Pulso"
        }
    }
}

/// Escala de color en 5 pasos, de turquesa (lento/bajo) a rojo (rápido/alto), legible
/// sobre mapas claros y oscuros. Siempre va con leyenda.
enum RunColorScale {
    static let steps: [Color] = [
        Color(HalsynRGBColor(hex: 0x1FB99A)),
        Color(HalsynRGBColor(hex: 0x9ACD5A)),
        Color(HalsynRGBColor(hex: 0xF2C14E)),
        Color(HalsynRGBColor(hex: 0xFF8A4C)),
        Color(HalsynRGBColor(hex: 0xE8452C)),
    ]

    /// Paso de color de cada valor según sus percentiles 10–90 (los extremos no dominan la escala).
    static func buckets(_ values: [Double?], higherIsStronger: Bool) -> [Int?] {
        let known = values.compactMap { $0 }.sorted()
        guard known.count >= 2 else { return values.map { $0 == nil ? nil : 2 } }
        let low = known[Int(Double(known.count - 1) * 0.1)]
        let high = known[Int(Double(known.count - 1) * 0.9)]
        return values.map { value in
            guard let value else { return nil }
            guard high > low else { return 2 }
            let fraction = min(max((value - low) / (high - low), 0), 1)
            let step = Int((fraction * Double(steps.count - 1)).rounded())
            return higherIsStronger ? step : steps.count - 1 - step
        }
    }
}

// MARK: - Mapa coloreado

struct RunColoredMap: View {
    let insights: RunInsights
    let isDemo: Bool
    @State private var coloring: RunColoring = .pace

    private var hasHeartRate: Bool { insights.segments.contains { $0.heartRate != nil } }

    private var colors: [Int?] {
        switch coloring {
        // Menos segundos por km = más rápido = más intenso.
        case .pace: RunColorScale.buckets(insights.segments.map { $0.pace?.secondsPerKilometer }, higherIsStronger: false)
        case .heartRate: RunColorScale.buckets(insights.segments.map(\.heartRate), higherIsStronger: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            HStack {
                HalsynSectionHeader("Ruta", eyebrow: HalsynLexicon.rorelse.rawValue)
                Spacer()
                if hasHeartRate {
                    Picker("Color", selection: $coloring) {
                        ForEach(RunColoring.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
            let buckets = colors
            Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
                ForEach(insights.segments) { segment in
                    MapPolyline(coordinates: WorkoutAnalysis.simplified(segment.points).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(buckets[segment.index].map { RunColorScale.steps[$0] } ?? Color.halsynSecondaryText, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let first = insights.segments.first?.points.first {
                    Annotation("Salida", coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)) {
                        Circle().fill(Color.halsynPositive).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
                if let last = insights.segments.last?.points.last {
                    Annotation("Llegada", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                        Circle().fill(Color.halsynAlert).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: HalsynRadius.card, style: .continuous))
            .accessibilityLabel(Text(coloring == .pace ? "Mapa de la ruta coloreado por ritmo" : "Mapa de la ruta coloreado por pulso"))

            HStack(spacing: 6) {
                Text(coloring == .pace ? "Más lento" : "Pulso más bajo")
                HStack(spacing: 2) {
                    ForEach(RunColorScale.steps.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2).fill(RunColorScale.steps[index]).frame(width: 18, height: 8)
                    }
                }
                Text(coloring == .pace ? "Más rápido" : "Pulso más alto")
            }
            .font(.caption2)
            .foregroundStyle(.halsynSecondaryText)
            .accessibilityElement(children: .combine)

            if isDemo {
                Text("Ruta de ejemplo (modo demo).")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }
}

// MARK: - Perfil de ritmo y pulso

/// Ritmo y pulso a lo largo de la distancia, en dos gráficas alineadas (sin doble eje).
struct RunProfileChart: View {
    let insights: RunInsights
    let unitSystem: UnitSystem
    @State private var selectedDistance: Double?

    private struct Point: Identifiable {
        let id: Int
        let distance: Double
        let pace: Double?
        let heartRate: Double?
    }

    private var points: [Point] {
        insights.segments.filter { $0.distance >= RunAnalyzer.segmentLength * 0.5 }.map { segment in
            Point(
                id: segment.index,
                distance: (segment.startDistance + segment.distance / 2) / unitSystem.metersPerDistanceUnit,
                // Ritmo en segundos por unidad mostrada.
                pace: segment.pace.map { $0.secondsPerKilometer * unitSystem.metersPerDistanceUnit / 1000 },
                heartRate: segment.heartRate
            )
        }
    }

    private var maxDistance: Double { insights.distance / unitSystem.metersPerDistanceUnit }

    private var selected: Point? {
        guard let selectedDistance else { return nil }
        return points.min { abs($0.distance - selectedDistance) < abs($1.distance - selectedDistance) }
    }

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    HalsynSectionHeader("Ritmo y pulso", eyebrow: HalsynLexicon.fart.rawValue)
                    Spacer()
                    if let selected {
                        // Lectura de la posición elegida en la cabecera.
                        Text(verbatim: readout(selected))
                            .font(.halsynCaption.monospacedDigit())
                            .foregroundStyle(.halsynPrimaryText)
                    }
                }
                paceChart
                if points.contains(where: { $0.heartRate != nil }) {
                    heartRateChart
                }
                Text("Cada punto es un tramo de 200 m, sin pausas. Arriba, más rápido.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    private func readout(_ point: Point) -> String {
        let distance = HalsynFormat.decimal(point.distance, fractionDigits: 1)
        let pace = point.pace.map { Pace(secondsPerKilometer: $0 * 1000 / unitSystem.metersPerDistanceUnit).formatted(in: unitSystem) } ?? "—"
        let pulse = point.heartRate.map { "\(Int($0.rounded())) lpm" } ?? ""
        return "\(distance) \(unitSystem.distanceUnitSymbol) · \(pace) \(unitSystem.paceUnitSymbol) \(pulse)"
    }

    private var paceChart: some View {
        Chart {
            ForEach(points) { point in
                if let pace = point.pace {
                    LineMark(x: .value("Distancia", point.distance), y: .value("Ritmo", pace), series: .value("Serie", "ritmo"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.halsynChart)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
            if let selected, let pace = selected.pace {
                RuleMark(x: .value("Distancia", selected.distance))
                    .foregroundStyle(Color.halsynSecondaryText.opacity(0.4))
                PointMark(x: .value("Distancia", selected.distance), y: .value("Ritmo", pace))
                    .foregroundStyle(Color.halsynChart)
            }
        }
        .chartXScale(domain: 0...max(maxDistance, 0.1))
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.halsynHairline)
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(verbatim: HalsynFormat.duration(seconds))
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartXSelection(value: $selectedDistance)
        .frame(height: 130)
        .accessibilityLabel(Text("Ritmo a lo largo de la carrera"))
    }

    private var heartRateChart: some View {
        Chart {
            ForEach(points) { point in
                if let heartRate = point.heartRate {
                    LineMark(x: .value("Distancia", point.distance), y: .value("lpm", heartRate), series: .value("Serie", "pulso"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.halsynAlert)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            if let selected {
                RuleMark(x: .value("Distancia", selected.distance))
                    .foregroundStyle(Color.halsynSecondaryText.opacity(0.4))
            }
        }
        .chartXScale(domain: 0...max(maxDistance, 0.1))
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(Color.halsynHairline)
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $selectedDistance)
        .frame(height: 110)
        .accessibilityLabel(Text("Pulso a lo largo de la carrera"))
    }
}

// MARK: - Cómo fue

/// Lectura de la carrera: eficiencia, deriva cardíaca, mitades, desnivel y regularidad.
struct RunAnalysisCard: View {
    let insights: RunInsights
    let unitSystem: UnitSystem

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Cómo fue", eyebrow: HalsynLexicon.form.rawValue)

                if let decoupling = insights.decoupling {
                    decouplingRow(decoupling)
                    Divider()
                }
                if let first = insights.firstHalf, let second = insights.secondHalf {
                    halves(first, second)
                    Divider()
                }
                HStack(alignment: .top, spacing: HalsynSpacing.m) {
                    if let meters = insights.metersPerBeat {
                        stat("Metros por latido", HalsynFormat.decimal(meters, fractionDigits: 2), "Cuánto avanzas con cada latido. Si sube con el tiempo a ritmos parecidos, estás más en forma.")
                    }
                    if insights.elevationGain >= 1 {
                        stat("Desnivel positivo", "\(HalsynFormat.integer(insights.elevationGain)) m", "Calculado con la altitud del GPS; puede tener unos metros de error.")
                    }
                }
                if let variability = insights.paceVariability {
                    stat("Regularidad", variabilityText(variability), "Variación del ritmo entre tramos de 200 m: \(HalsynFormat.decimal(variability, fractionDigits: 1)) por ciento.")
                }
            }
        }
    }

    private func decouplingRow(_ value: Double) -> some View {
        let (title, level): (LocalizedStringKey, HalsynStatusIndicator.Level) = switch value {
        case ..<5: ("Pulso estable de principio a fin", .positive)
        case ..<10: ("El pulso subió algo al final", .neutral)
        default: ("El pulso subió bastante al final", .caution)
        }
        return VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Deriva cardíaca")
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                Spacer()
                Text(verbatim: "\(value >= 0 ? "+" : "")\(HalsynFormat.decimal(value, fractionDigits: 1)) %")
                    .font(.halsynMetricValue)
                    .foregroundStyle(.halsynPrimaryText)
            }
            Label { Text(title) } icon: { Image(systemName: level == .caution ? "arrow.up.heart" : "heart") }
                .font(.halsynCaption)
                .foregroundStyle(level == .caution ? Color.halsynCaution : Color.halsynSecondaryText)
            Text("Compara cuánto avanzas por latido en la primera y la segunda mitad (sin los primeros \(HalsynFormat.duration(insights.warmup)) de calentamiento). Por debajo del 5 por ciento suele indicar que el ritmo era sostenible para tu base aeróbica; el calor, el cansancio, la falta de agua o un ritmo exigente la suben. Solo tiene sentido en carreras de ritmo continuo.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func halves(_ first: RunHalf, _ second: RunHalf) -> some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            HStack {
                Text("Primera y segunda mitad")
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                Spacer()
                if let difference = insights.halfPaceDifference, abs(difference) >= 3 {
                    Text(difference < 0 ? "Acabaste más rápido" : "Acabaste más lento")
                        .font(.halsynCaption)
                        .foregroundStyle(difference < 0 ? Color.halsynPositive : Color.halsynSecondaryText)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: HalsynSpacing.m, verticalSpacing: 4) {
                GridRow {
                    Text(verbatim: "")
                    Text("Ritmo").font(.caption2).foregroundStyle(.halsynSecondaryText)
                    Text("Pulso").font(.caption2).foregroundStyle(.halsynSecondaryText)
                }
                halfRow("1.ª mitad", first)
                halfRow("2.ª mitad", second)
            }
        }
    }

    private func halfRow(_ title: LocalizedStringKey, _ half: RunHalf) -> some View {
        GridRow {
            Text(title).font(.halsynCaption).foregroundStyle(.halsynSecondaryText)
            Text(verbatim: "\(half.pace?.formatted(in: unitSystem) ?? "—") \(unitSystem.paceUnitSymbol)")
                .font(.halsynCaption.monospacedDigit())
            Text(verbatim: half.heartRate.map { "\(Int($0.rounded())) lpm" } ?? "—")
                .font(.halsynCaption.monospacedDigit())
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, _ note: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
            Text(verbatim: value)
                .font(.halsynMetricValue)
                .foregroundStyle(.halsynPrimaryText)
            Text(note)
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func variabilityText(_ value: Double) -> String {
        switch value {
        case ..<4: String(localized: "Muy regular")
        case ..<8: String(localized: "Regular")
        default: String(localized: "Con cambios de ritmo")
        }
    }
}

// MARK: - Frente a carreras parecidas

struct SimilarRunsCard: View {
    let comparison: SimilarRunComparison
    let unitSystem: UnitSystem

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Frente a tus carreras parecidas", eyebrow: HalsynModule.insikt.brandName)
                Text(headline)
                    .font(.halsynBody)
                    .foregroundStyle(.halsynPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: HalsynSpacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Puesto por ritmo").font(.caption2).foregroundStyle(.halsynSecondaryText)
                        Text(verbatim: "\(comparison.paceRank) / \(comparison.count + 1)")
                            .font(.halsynMetricValue)
                    }
                    if let rank = comparison.efficiencyRank {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Puesto por eficiencia").font(.caption2).foregroundStyle(.halsynSecondaryText)
                            Text(verbatim: "\(rank) / \(comparison.efficiencyCount)")
                                .font(.halsynMetricValue)
                        }
                    }
                    Spacer()
                }
                Text("Comparada con \(comparison.count) carreras tuyas de distancia parecida (±25 por ciento). La eficiencia son los metros por latido: tiene en cuenta que ir más rápido cuesta más pulso.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headline: LocalizedStringKey {
        let seconds = abs(comparison.paceDifference) * unitSystem.metersPerDistanceUnit / 1000
        let amount = HalsynFormat.duration(seconds)
        let median = "\(comparison.medianPace.formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol)"
        if seconds < 3 {
            return "Ritmo igual a tu mediana en esta distancia (\(median))."
        }
        return comparison.paceDifference < 0
            ? "\(amount) por \(unitSystem.distanceUnitSymbol) más rápida que tu mediana en esta distancia (\(median))."
            : "\(amount) por \(unitSystem.distanceUnitSymbol) más lenta que tu mediana en esta distancia (\(median))."
    }
}
