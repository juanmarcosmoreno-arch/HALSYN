import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

/// Detalle de una salida en bici: métricas, potencia (con medidor), ruta,
/// perfil de altitud y velocidad, parciales de 5 km y FC por zonas.
/// Lo que Apple Health no tiene (sin GPS, sin medidor) no se muestra ni se inventa.
struct RideDetailView: View {
    let ride: WorkoutSummary
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var detail: WorkoutDetailData?
    @State private var ftpStore = FTPStore.shared
    @State private var settings = RunSettingsStore.shared

    private let columns = [GridItem(.flexible(), spacing: HalsynSpacing.s), GridItem(.flexible(), spacing: HalsynSpacing.s)]

    var body: some View {
        HalsynScreen {
            header

            LazyVGrid(columns: columns, spacing: HalsynSpacing.s) {
                HalsynMetricTile(title: "Tiempo", systemImage: "stopwatch", value: HalsynFormat.duration(ride.duration), unit: "")
                HalsynMetricTile(title: "Velocidad media", systemImage: "speedometer", value: ride.averageSpeed?.formatted(in: unitSystem), unit: unitSystem.speedUnitSymbol, status: ride.averageSpeed == nil ? "Sin distancia" : nil)
                HalsynMetricTile(title: "FC media", systemImage: "heart", value: ride.averageHeartRate.map { HalsynFormat.integer($0) }, unit: "lpm", status: ride.averageHeartRate == nil ? "No medida" : nil)
                HalsynMetricTile(title: "FC máx. registrada", systemImage: "heart.fill", value: ride.maxHeartRate.map { HalsynFormat.integer($0) }, unit: "lpm", status: ride.maxHeartRate == nil ? "No medida" : nil)
                HalsynMetricTile(title: "Desnivel", systemImage: "mountain.2", value: elevationGain.map { HalsynFormat.integer($0) }, unit: "m", status: elevationGain == nil ? "No medido" : nil)
                HalsynMetricTile(title: "Potencia media", systemImage: "bolt", value: ride.averagePower.map { HalsynFormat.integer($0) }, unit: "W", status: ride.averagePower == nil ? "Sin medidor" : nil)
                HalsynMetricTile(title: "Cadencia", systemImage: "arrow.triangle.2.circlepath", value: ride.averageCadence.map { HalsynFormat.integer($0) }, unit: "rpm", status: ride.averageCadence == nil ? "Sin sensor" : nil)
                HalsynMetricTile(title: "Energía activa", systemImage: "flame", value: ride.activeEnergyKilocalories.map { HalsynFormat.integer($0) }, unit: "kcal")
            }

            if let detail {
                if let power = PowerAnalysis.summary(detail.power) {
                    RidePowerCard(summary: power, samples: detail.power, start: ride.start, ftp: ftpStore.resolved(manual: settings.settings.validFunctionalThresholdPower))
                }
                if detail.route.count > 1 {
                    WorkoutRouteMap(route: detail.route, isDemo: detail.origin.isDemo)
                    RideProfileCard(route: detail.route, unitSystem: unitSystem)
                    splitsSection(detail.route)
                } else if ride.activity == .outdoorRide {
                    HalsynCard {
                        HalsynEmptyState(systemImage: "map", title: "Sin ruta", message: "Esta salida no tiene ruta GPS en Apple Health, o HÅLSYN no tiene permiso para leerla.")
                    }
                }
                if !detail.heartRate.isEmpty {
                    HeartRateZonesCard(samples: detail.heartRate, note: "Zonas de SPRING. En bici la FC suele ser algo más baja que corriendo al mismo esfuerzo: tómalas como orientación.")
                }
            } else {
                HalsynLoadingState()
            }

            DataOriginFootnote(origin: ride.origin)
        }
        .navigationTitle(Text(LocalizedStringKey(ride.activity.title)))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ride.id) {
            await ftpStore.loadHealthIfNeeded(provider: model.provider)
            detail = await model.provider.workoutDetail(for: ride)
        }
    }

    /// El guardado en Salud y, si no lo hay, el calculado con la altitud GPS de la ruta.
    private var elevationGain: Double? {
        ride.elevationGain ?? detail.flatMap { RideAnalysis.elevationGain($0.route) }
    }

    private var header: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HStack {
                    Label(LocalizedStringKey(ride.activity.title), systemImage: ride.activity.systemImage)
                        .halsynEyebrowStyle()
                    Spacer()
                    if ride.origin.isDemo { HalsynDemoBadge() }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let distance = ride.distanceMeters, distance > 0 {
                        Text(verbatim: HalsynFormat.distance(meters: distance, unit: unitSystem))
                            .font(.system(size: 52, weight: .light).monospacedDigit())
                            .foregroundStyle(.halsynPrimaryText)
                        Text(verbatim: unitSystem.distanceUnitSymbol)
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynSecondaryText)
                    } else {
                        Text(verbatim: HalsynFormat.duration(ride.duration))
                            .font(.system(size: 52, weight: .light).monospacedDigit())
                            .foregroundStyle(.halsynPrimaryText)
                    }
                }
                Text(ride.start, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                if ride.distanceMeters == nil && ride.activity == .indoorRide {
                    Text("En interior el reloj solo mide distancia con un sensor de velocidad o un rodillo que la envíe.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
    }

    // MARK: Parciales de 5 km

    @ViewBuilder
    private func splitsSection(_ route: [LocationSample]) -> some View {
        let splits = RideAnalysis.splits(from: route, unit: unitSystem)
        if splits.count > 1 {
            let speeds = splits.compactMap { $0.speed?.metersPerSecond }
            let fastest = speeds.max() ?? 1
            let slowest = speeds.min() ?? 0
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HalsynSectionHeader(unitSystem == .imperial ? "Parciales de 5 mi" : "Parciales de 5 km", eyebrow: HalsynLexicon.fart.rawValue)
                    ForEach(splits) { split in
                        HStack(spacing: HalsynSpacing.s) {
                            Text(verbatim: split.isComplete ? SessionText.distance(Double(split.index) * unitSystem.metersPerDistanceUnit * 5, unit: unitSystem) : "+" + HalsynFormat.distance(meters: split.distance, unit: unitSystem))
                                .font(.halsynCaption.monospacedDigit())
                                .foregroundStyle(.halsynSecondaryText)
                                .frame(width: 64, alignment: .leading)
                            GeometryReader { proxy in
                                let value = split.speed?.metersPerSecond ?? slowest
                                // Barra más larga = más rápido.
                                let fraction = fastest > slowest ? 0.35 + 0.65 * (value - slowest) / (fastest - slowest) : 1
                                Capsule()
                                    .fill(Color.halsynAccent.opacity(value == fastest ? 1 : 0.55))
                                    .frame(width: proxy.size.width * fraction)
                            }
                            .frame(height: 10)
                            Text(verbatim: "\(split.speed?.formatted(in: unitSystem) ?? "—") \(unitSystem.speedUnitSymbol)")
                                .font(.halsynCaption.monospacedDigit())
                                .foregroundStyle(.halsynPrimaryText)
                                .frame(width: 84, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("Calculados a partir de la ruta GPS, sin contar las paradas largas; pueden diferir ligeramente de la distancia total de Apple Health.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
    }
}

/// Potencia de la salida: media, ponderada, mejores 20 min, intensidad, carga
/// y tiempo en zonas (con FTP). Método de Coggan (potencia normalizada,
/// factor de intensidad y TSS, marcas de TrainingPeaks).
private struct RidePowerCard: View {
    let summary: PowerSummary
    let samples: [PowerSample]
    let start: Date
    let ftp: ResolvedFTP?

    private let columns = [GridItem(.flexible(), spacing: HalsynSpacing.s), GridItem(.flexible(), spacing: HalsynSpacing.s)]

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Potencia", eyebrow: HalsynLexicon.kraft.rawValue)
                LazyVGrid(columns: columns, alignment: .leading, spacing: HalsynSpacing.m) {
                    HalsynMetric(title: "Media", value: HalsynFormat.integer(summary.averagePower), unit: "W")
                    HalsynMetric(title: "Ponderada (NP)", value: summary.normalizedPower.map { HalsynFormat.integer($0) }, unit: "W")
                    HalsynMetric(title: "Mejores 20 min", value: summary.best20Minutes.map { HalsynFormat.integer($0) }, unit: "W")
                    HalsynMetric(title: "Máxima", value: HalsynFormat.integer(summary.maxPower), unit: "W")
                    if let ftp {
                        HalsynMetric(title: "Intensidad (IF)", value: summary.intensityFactor(ftp: ftp.watts).map { HalsynFormat.decimal($0, fractionDigits: 2) }, unit: "")
                        HalsynMetric(title: "Carga (TSS)", value: summary.trainingStressScore(ftp: ftp.watts).map { HalsynFormat.integer($0) }, unit: "")
                    }
                }
                chart
                if let ftp {
                    zoneBars(ftp: ftp.watts)
                    Text("Con tu FTP de \(HalsynFormat.integer(ftp.watts)) W. Una hora entera a tu FTP son 100 de carga; la intensidad es la ponderada dividida entre el FTP.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                } else {
                    Text("Escribe tu FTP en CYKEL › Potencia y FTP para ver la intensidad, la carga y el tiempo en cada zona.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
                Text("La ponderada da más peso a los tramos fuertes: refleja mejor el esfuerzo de una salida con cambios de ritmo que la media. Método de Coggan; potencia normalizada (NP), factor de intensidad (IF) y TSS son marcas de TrainingPeaks.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    /// Media de cada 30 s, en minutos desde la salida.
    private var points: [(minute: Double, watts: Double)] {
        var buckets: [Int: (sum: Double, count: Int)] = [:]
        for sample in samples {
            let key = Int(sample.start.timeIntervalSince(start) / 30)
            guard key >= 0 else { continue }
            buckets[key, default: (0, 0)].sum += sample.watts
            buckets[key, default: (0, 0)].count += 1
        }
        return buckets.keys.sorted().compactMap { key in
            guard let bucket = buckets[key], bucket.count > 0 else { return nil }
            return (Double(key) / 2, bucket.sum / Double(bucket.count))
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points, id: \.minute) { point in
                LineMark(x: .value("Minuto", point.minute), y: .value("W", point.watts))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.halsynAccent)
            }
            if let ftp {
                RuleMark(y: .value("FTP", ftp.watts))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.halsynSecondaryText)
                    .annotation(position: .top, alignment: .leading) {
                        Text(verbatim: "FTP")
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                    }
            }
        }
        .chartXAxisLabel(Text("min"))
        .frame(height: 140)
        .accessibilityLabel(Text("Gráfico de potencia"))
    }

    private func zoneBars(ftp: Double) -> some View {
        let seconds = PowerAnalysis.zoneSeconds(segments: PowerAnalysis.secondsSeries(samples), ftp: ftp)
        let total = max(seconds.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            Text("Tiempo en zonas de potencia")
                .font(.halsynHeadline)
                .foregroundStyle(.halsynPrimaryText)
            ForEach(PowerZones.zones.reversed()) { zone in
                HStack(spacing: HalsynSpacing.s) {
                    Text(verbatim: "Z\(zone.index)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 30)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(PowerZoneColors.color(zone.index)))
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.halsynHairline)
                            Capsule()
                                .fill(PowerZoneColors.color(zone.index))
                                .frame(width: max(4, proxy.size.width * seconds[zone.index] / total))
                        }
                    }
                    .frame(height: 10)
                    Text(verbatim: HalsynFormat.duration(seconds[zone.index]))
                        .font(.halsynCaption.monospacedDigit())
                        .frame(width: 56, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Altitud (área) y velocidad (línea) a lo largo de la distancia.
private struct RideProfileCard: View {
    let route: [LocationSample]
    let unitSystem: UnitSystem

    var body: some View {
        let profile = RideAnalysis.profile(from: route)
        let altitudes = profile.compactMap(\.altitude)
        if profile.count > 2 {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                    HalsynSectionHeader("Perfil", eyebrow: HalsynLexicon.fart.rawValue)
                    if altitudes.count > 2, let low = altitudes.min(), let high = altitudes.max() {
                        Chart {
                            ForEach(Array(profile.enumerated()), id: \.offset) { _, point in
                                if let altitude = point.altitude {
                                    AreaMark(x: .value("Distancia", point.distance / unitSystem.metersPerDistanceUnit), yStart: .value("Base", low - 5), yEnd: .value("Altitud", altitude))
                                        .foregroundStyle(Color.halsynChart.opacity(0.35))
                                        .interpolationMethod(.monotone)
                                }
                            }
                        }
                        .chartYScale(domain: (low - 5)...(high + 5))
                        .chartXAxisLabel(Text(verbatim: unitSystem.distanceUnitSymbol))
                        .chartYAxisLabel(Text(verbatim: "m"))
                        .frame(height: 110)
                        .accessibilityLabel(Text("Perfil de altitud"))
                    }
                    Chart {
                        ForEach(Array(profile.enumerated()), id: \.offset) { _, point in
                            if let speed = point.speed {
                                LineMark(x: .value("Distancia", point.distance / unitSystem.metersPerDistanceUnit), y: .value("Velocidad", speed.value(in: unitSystem)))
                                    .foregroundStyle(Color.halsynAccent)
                                    .interpolationMethod(.monotone)
                            }
                        }
                    }
                    .chartXAxisLabel(Text(verbatim: unitSystem.distanceUnitSymbol))
                    .chartYAxisLabel(Text(verbatim: unitSystem.speedUnitSymbol))
                    .frame(height: 110)
                    .accessibilityLabel(Text("Velocidad a lo largo de la salida"))
                    Text("Altitud y velocidad según el GPS del reloj (la altitud GPS es aproximada).")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RideDetailView(ride: WorkoutSummary(activity: .outdoorRide, start: .now, duration: 5400, distanceMeters: 42_300, averageHeartRate: 138, maxHeartRate: 166, activeEnergyKilocalories: 820, averageCadence: 86, origin: .demo, averagePower: 192, elevationGain: 420))
    }
    .environment(AppModel())
}
