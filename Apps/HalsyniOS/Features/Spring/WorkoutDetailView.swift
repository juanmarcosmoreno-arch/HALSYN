import Charts
import HalsynCore
import HalsynDesign
import MapKit
import SwiftUI

/// Detalle de un entrenamiento: métricas, ruta, parciales, FC y tiempo en zonas.
/// Ruta y FC se leen de Apple Health; si no existen (cinta, sin permiso) se dice.
struct WorkoutDetailView: View {
    let workout: WorkoutSummary
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var detail: WorkoutDetailData?

    private let columns = [GridItem(.flexible(), spacing: HalsynSpacing.s), GridItem(.flexible(), spacing: HalsynSpacing.s)]

    var body: some View {
        HalsynScreen {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HStack {
                        Label(LocalizedStringKey(workout.activity.title), systemImage: workout.activity.systemImage)
                            .halsynEyebrowStyle()
                        Spacer()
                        if workout.origin.isDemo { HalsynDemoBadge() }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: workout.distanceMeters.map { HalsynFormat.distance(meters: $0, unit: unitSystem) } ?? "—")
                            .font(.system(size: 52, weight: .light).monospacedDigit())
                            .foregroundStyle(.halsynPrimaryText)
                        Text(verbatim: unitSystem.distanceUnitSymbol)
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    Text(workout.start, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }

            LazyVGrid(columns: columns, spacing: HalsynSpacing.s) {
                HalsynMetricTile(title: "Tiempo", systemImage: "stopwatch", value: HalsynFormat.duration(workout.duration), unit: "")
                HalsynMetricTile(title: "Ritmo medio", systemImage: "speedometer", value: workout.averagePace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol)
                HalsynMetricTile(title: "FC media", systemImage: "heart", value: workout.averageHeartRate.map { String(Int($0)) }, unit: "lpm", status: workout.averageHeartRate == nil ? "No medida" : nil)
                HalsynMetricTile(title: "FC máx. registrada", systemImage: "heart.fill", value: workout.maxHeartRate.map { String(Int($0)) }, unit: "lpm", status: workout.maxHeartRate == nil ? "No medida" : nil)
                HalsynMetricTile(title: "Cadencia", systemImage: "metronome", value: workout.averageCadence.map { String(Int($0)) }, unit: "ppm", status: workout.averageCadence == nil ? "No medida" : nil)
                HalsynMetricTile(title: "Energía activa", systemImage: "flame", value: workout.activeEnergyKilocalories.map { String(Int($0)) }, unit: "kcal")
            }

            if let detail {
                routeSection(detail)
                splitsSection(detail)
                heartRateSection(detail)
            } else {
                HalsynLoadingState()
            }

            DataOriginFootnote(origin: workout.origin)
        }
        .navigationTitle(Text(LocalizedStringKey(workout.activity.title)))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workout.id) {
            detail = await model.provider.workoutDetail(for: workout)
        }
    }

    // MARK: Ruta

    @ViewBuilder
    private func routeSection(_ detail: WorkoutDetailData) -> some View {
        if detail.route.count > 1 {
            let points = WorkoutAnalysis.simplified(detail.route).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Ruta", eyebrow: HalsynLexicon.rorelse.rawValue)
                Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
                    MapPolyline(coordinates: points)
                        .stroke(Color.halsynAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    if let first = points.first {
                        Annotation("Salida", coordinate: first) {
                            Circle().fill(Color.halsynPositive).frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        }
                    }
                    if let last = points.last {
                        Annotation("Llegada", coordinate: last) {
                            Circle().fill(Color.halsynAlert).frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        }
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: HalsynRadius.card, style: .continuous))
                .accessibilityLabel(Text("Mapa de la ruta"))
                if detail.origin.isDemo {
                    Text("Ruta de ejemplo (modo demo).")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        } else if workout.activity == .outdoorRun {
            HalsynCard {
                HalsynEmptyState(systemImage: "map", title: "Sin ruta", message: "Este entrenamiento no tiene ruta GPS en Apple Health, o HÅLSYN no tiene permiso para leerla.")
            }
        }
    }

    // MARK: Parciales

    @ViewBuilder
    private func splitsSection(_ detail: WorkoutDetailData) -> some View {
        let splits = WorkoutAnalysis.splits(from: detail.route, unit: unitSystem)
        if !splits.isEmpty {
            let paces = splits.compactMap { $0.pace?.secondsPerKilometer }
            let fastest = paces.min() ?? 0
            let slowest = paces.max() ?? 1
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HalsynSectionHeader("Parciales", eyebrow: HalsynLexicon.fart.rawValue)
                    ForEach(splits) { split in
                        HStack(spacing: HalsynSpacing.s) {
                            Text(verbatim: split.isComplete ? "\(split.index)" : HalsynFormat.distance(meters: split.distance, unit: unitSystem))
                                .font(.halsynCaption.monospacedDigit())
                                .foregroundStyle(.halsynSecondaryText)
                                .frame(width: 44, alignment: .leading)
                            GeometryReader { proxy in
                                let value = split.pace?.secondsPerKilometer ?? slowest
                                // Barra más larga = más rápido.
                                let fraction = slowest > fastest ? 0.35 + 0.65 * (slowest - value) / (slowest - fastest) : 1
                                Capsule()
                                    .fill(Color.halsynAccent.opacity(value == fastest ? 1 : 0.55))
                                    .frame(width: proxy.size.width * fraction)
                            }
                            .frame(height: 10)
                            Text(verbatim: "\(split.pace?.formatted(in: unitSystem) ?? "—") \(unitSystem.paceUnitSymbol)")
                                .font(.halsynCaption.monospacedDigit())
                                .foregroundStyle(.halsynPrimaryText)
                                .frame(width: 84, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("Calculados a partir de la ruta GPS; pueden diferir ligeramente de la distancia total de Apple Health.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
    }

    // MARK: FC y zonas

    @ViewBuilder
    private func heartRateSection(_ detail: WorkoutDetailData) -> some View {
        if !detail.heartRate.isEmpty {
            let zones = RunSettingsStore.shared.settings.zones
            let zoneSeconds = WorkoutAnalysis.zoneSeconds(detail.heartRate, zones: zones)
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                    HalsynSectionHeader("Frecuencia cardíaca", eyebrow: HalsynLexicon.puls.rawValue)
                    Chart(detail.heartRate, id: \.date) { point in
                        LineMark(x: .value("Hora", point.date), y: .value("lpm", point.bpm))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color.halsynAlert)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 140)
                    .accessibilityLabel(Text("Gráfico de frecuencia cardíaca"))

                    if zoneSeconds.isEmpty {
                        Label("Configura tus zonas en SPRING › Ajustes de carrera para ver el tiempo en cada zona.", systemImage: "heart.text.square")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    } else {
                        ZoneDistributionView(seconds: zoneSeconds, zones: zones.zones)
                    }
                }
            }
        }
    }
}

/// Tiempo en cada zona con su rango en lpm.
struct ZoneDistributionView: View {
    let seconds: [TimeInterval]
    let zones: [HeartRateZone]

    var body: some View {
        let total = max(seconds.reduce(0, +), 1)
        VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            Text("Tiempo en zonas")
                .font(.halsynHeadline)
                .foregroundStyle(.halsynPrimaryText)
            ForEach(zones.reversed()) { zone in
                let time = seconds.indices.contains(zone.index) ? seconds[zone.index] : 0
                HStack(spacing: HalsynSpacing.s) {
                    Text(verbatim: "Z\(zone.index)")
                        .font(.halsynCaption.monospacedDigit().weight(.semibold))
                        .frame(width: 26, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.halsynHairline)
                            Capsule()
                                .fill(Color.halsynAlert.opacity(0.3 + 0.14 * Double(zone.index)))
                                .frame(width: max(4, proxy.size.width * time / total))
                        }
                    }
                    .frame(height: 10)
                    Text(verbatim: HalsynFormat.duration(time))
                        .font(.halsynCaption.monospacedDigit())
                        .frame(width: 56, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Según tus zonas actuales (\(Int(zones.first?.lowerBound ?? 0))–\(Int(zones.last?.upperBound ?? 0)) lpm).")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
    }
}

/// Vista previa de una pantalla de entrenamiento con forma de Apple Watch.
/// Muestra valores de ejemplo (`DemoWorkoutSample`), nunca datos reales.
struct WatchScreenPreview: View {
    let profile: WorkoutScreenProfile
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        let sample = DemoWorkoutSample()
        HalsynWorkoutScreen(profile: profile) { sample.value(for: $0, unit: unitSystem) }
            .padding(12)
            .aspectRatio(0.82, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color(HalsynPalette.darkSurface), lineWidth: 6)
            )
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Vista previa del perfil \(profile.name) con valores de ejemplo"))
    }
}

#Preview {
    NavigationStack {
        WorkoutDetailView(workout: WorkoutSummary(activity: .outdoorRun, start: .now, duration: 1476, distanceMeters: 5210, averageHeartRate: 148, maxHeartRate: 167, activeEnergyKilocalories: 354, averageCadence: 172, origin: .demo))
    }
    .environment(AppModel())
}
