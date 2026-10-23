import HalsynCore
import HalsynDesign
import MapKit
import SwiftUI

/// Pantalla de carrera, deslizando en horizontal:
/// controles · intervalo (si hay plan) · pantallas de métricas configuradas · mapa (exterior) · vueltas.
/// Al terminar muestra el resumen.
struct WorkoutSessionView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        if workout.outcome != nil || workout.phase == .ended {
            WorkoutSummaryView()
        } else if workout.phase == .preparing {
            VStack(spacing: 8) {
                HalsynSymbol().frame(height: 44)
                ProgressView()
                Text("Preparando…").font(.footnote)
            }
        } else {
            WorkoutPagesView()
        }
    }
}

@MainActor private var unitSystem: UnitSystem { RunSettingsStore.shared.settings.unitSystem }

private struct WorkoutPagesView: View {
    enum Page: Hashable {
        case controls, interval, screen(Int), chart, map, laps
    }

    @Environment(WorkoutManager.self) private var workout
    @State private var page: Page = .screen(0)

    var body: some View {
        TabView(selection: $page) {
            WorkoutControlsView().tag(Page.controls)
            if workout.plan != nil {
                WorkoutIntervalView().tag(Page.interval)
            }
            ForEach(Array(workout.screens.enumerated()), id: \.offset) { index, profile in
                WorkoutMetricsView(profile: profile).tag(Page.screen(index))
            }
            WorkoutChartView().tag(Page.chart)
            if !workout.isIndoor {
                WorkoutMapView().tag(Page.map)
            }
            WorkoutLapsView().tag(Page.laps)
        }
        .tabViewStyle(.page)
        .onAppear {
            page = workout.plan != nil ? .interval : .screen(0)
        }
        .onChange(of: workout.phase) { _, phase in
            // Al pausar o reanudar se vuelve a la pantalla principal.
            if phase == .running || phase == .paused {
                withAnimation { page = workout.plan != nil ? .interval : .screen(0) }
            }
        }
    }
}

/// Aviso breve (vuelta, cambio de paso, alerta) sobre las métricas.
private struct BannerOverlay: View {
    let banner: WorkoutManager.Banner?
    let now: Date

    var body: some View {
        if let banner, now.timeIntervalSince(banner.date) < 4 {
            VStack(spacing: 0) {
                Text(verbatim: banner.title)
                    .font(.footnote.weight(.semibold))
                if let detail = banner.detail {
                    Text(verbatim: detail).font(.caption2.monospacedDigit())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(HalsynPalette.darkPrimary)))
            .foregroundStyle(Color.white)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct PausedLabel: View {
    var body: some View {
        Label("En pausa", systemImage: "pause.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(HalsynPalette.cautionDark))
    }
}

/// Métricas en vivo con un perfil de pantalla configurado en el iPhone.
private struct WorkoutMetricsView: View {
    let profile: WorkoutScreenProfile
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 1 : 0.5)) { context in
            let snapshot = workout.snapshot(at: context.date)
            VStack(alignment: .leading, spacing: 2) {
                if workout.phase == .paused {
                    PausedLabel()
                } else if let zone = snapshot.heartRateZone {
                    HalsynZoneGauge(zone: zone)
                }
                HalsynWorkoutScreen(profile: profile) { snapshot.value(for: $0, unit: unitSystem) }
            }
            .padding(.horizontal, 4)
            .overlay(alignment: .top) {
                BannerOverlay(banner: workout.banner, now: context.date)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// Ritmo (o FC, tocando) dibujándose a medida que corres.
private struct WorkoutChartView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let snapshot = workout.snapshot(at: context.date)
            HalsynLiveRunChart(
                paceSamples: snapshot.paceSamples,
                heartRateSamples: snapshot.heartRateSamples,
                averagePace: snapshot.averagePace,
                currentPace: snapshot.currentPace,
                heartRate: snapshot.heartRate,
                paceTarget: snapshot.paceTarget,
                unit: unitSystem
            )
            .padding(.horizontal, 4)
            .overlay(alignment: .top) {
                BannerOverlay(banner: workout.banner, now: context.date)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// Paso actual de los intervalos: qué toca, cuánto falta y el ritmo objetivo.
private struct WorkoutIntervalView: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 1 : 0.5)) { context in
            let snapshot = workout.snapshot(at: context.date)
            VStack(alignment: .leading, spacing: 4) {
                if workout.phase == .paused {
                    PausedLabel()
                }
                if let interval = snapshot.interval {
                    header(interval)
                    HalsynWorkoutField(label: interval.step.goal == .open ? "TID" : "QUEDAN", value: snapshot.value(for: .intervalTime, unit: unitSystem).value, unit: snapshot.value(for: .intervalTime, unit: unitSystem).unit, size: .large, emphasis: tint(interval.step.kind))
                    if let fraction = interval.fraction {
                        ProgressView(value: fraction)
                            .tint(tint(interval.step.kind))
                    } else {
                        Text("Pulsa Vuelta para continuar")
                            .font(.caption2)
                            .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                    }
                    HStack {
                        HalsynWorkoutField(label: "RITMO", value: snapshot.currentPace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol, size: .small)
                        if let target = snapshot.paceTarget {
                            HalsynWorkoutField(label: "OBJETIVO", value: target.formatted(in: unitSystem), unit: "", size: .small)
                        } else {
                            HalsynWorkoutField(label: "PULS", value: snapshot.value(for: .heartRate).value, unit: "lpm", size: .small, emphasis: Color(HalsynPalette.alertDark))
                        }
                    }
                } else {
                    Label(snapshot.intervalsCompleted ? LocalizedStringKey("Intervalos completados") : LocalizedStringKey("Carrera libre"), systemImage: "checkmark.circle")
                        .font(.headline)
                        .foregroundStyle(Color(HalsynPalette.darkAccent))
                    HalsynWorkoutScreen(profile: workout.screens.first ?? .easyRun) { snapshot.value(for: $0, unit: unitSystem) }
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .top) {
                BannerOverlay(banner: workout.banner, now: context.date)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func header(_ interval: IntervalProgress) -> some View {
        HStack {
            Text(LocalizedStringKey(interval.step.kind.label))
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(tint(interval.step.kind))
            Spacer()
            if let repetition = interval.step.repetition {
                Text(verbatim: "\(repetition)/\(workout.plan?.repeats ?? repetition)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.white)
            }
        }
    }

    private func tint(_ kind: IntervalStepKind) -> Color {
        switch kind {
        case .work: Color(HalsynPalette.alertDark)
        case .recovery: Color(HalsynPalette.darkAccent)
        case .warmup, .cooldown: Color(HalsynPalette.cautionDark)
        }
    }
}

/// Mapa con la ruta recorrida (puntos fiables) y la posición actual.
private struct WorkoutMapView: View {
    @Environment(WorkoutManager.self) private var workout
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $position) {
            if workout.routeCoordinates.count > 1 {
                MapPolyline(coordinates: workout.routeCoordinates)
                    .stroke(Color(HalsynPalette.darkAccent), lineWidth: 4)
            }
            UserAnnotation()
        }
        .overlay(alignment: .bottom) {
            if workout.routeCoordinates.isEmpty {
                Text("Buscando GPS…")
                    .font(.caption2)
                    .padding(4)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
            }
        }
        .accessibilityLabel(Text("Mapa de la ruta"))
    }
}

private struct WorkoutControlsView: View {
    @Environment(WorkoutManager.self) private var workout
    @State private var confirmingEnd = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                controlButton(
                    workout.phase == .paused ? "Reanudar" : "Pausa",
                    systemImage: workout.phase == .paused ? "play.fill" : "pause.fill",
                    tint: Color(HalsynPalette.cautionDark)
                ) {
                    workout.togglePause()
                }
                controlButton("Vuelta", systemImage: "flag.fill", tint: Color(HalsynPalette.darkAccent)) {
                    workout.markLap()
                }
                .disabled(workout.phase != .running)
            }
            controlButton("Terminar", systemImage: "xmark", tint: Color(HalsynPalette.alertDark)) {
                confirmingEnd = true
            }
        }
        .confirmationDialog("¿Terminar la carrera?", isPresented: $confirmingEnd) {
            Button("Guardar en Apple Health") { workout.end(save: true) }
            Button("Descartar", role: .destructive) { workout.end(save: false) }
            Button("Seguir corriendo", role: .cancel) {}
        }
    }

    private func controlButton(_ title: LocalizedStringKey, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 52, height: 40)
                    .background(Capsule().fill(tint.opacity(0.25)))
                    .foregroundStyle(tint)
                Text(title).font(.caption2)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct WorkoutLapsView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        let laps = workout.snapshot(at: .now).laps
        List {
            if laps.isEmpty {
                Text("Sin vueltas todavía").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(laps.reversed()) { lap in
                HStack {
                    Text(verbatim: "\(lap.index)").font(.headline.monospacedDigit())
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(verbatim: HalsynFormat.duration(lap.duration)).monospacedDigit()
                        Text(verbatim: "\(lap.pace?.formatted(in: unitSystem) ?? "--") \(unitSystem.paceUnitSymbol)")
                            .font(.caption2)
                            .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                    }
                }
            }
        }
    }
}

/// Resumen al terminar.
private struct WorkoutSummaryView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        let snapshot = workout.snapshot(at: .now)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch workout.outcome {
                case .saved:
                    Label("Guardada en Apple Health", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color(HalsynPalette.darkAccent))
                case .discarded:
                    Label("Carrera descartada", systemImage: "trash")
                        .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                case .failed:
                    Label("No se pudo completar", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(HalsynPalette.cautionDark))
                    if let message = workout.errorMessage {
                        Text(verbatim: message).font(.caption2)
                    }
                case nil:
                    ProgressView()
                }
                if let name = snapshot.intervalPlanName {
                    Text(verbatim: name)
                        .font(.headline)
                        .foregroundStyle(Color(HalsynPalette.darkAccent))
                }
                HalsynWatchMetric(title: "Distancia", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: HalsynFormat.distance(meters: snapshot.distance, unit: unitSystem), unit: unitSystem.distanceUnitSymbol)
                HalsynWatchMetric(title: "Tiempo", systemImage: "stopwatch", value: HalsynFormat.duration(snapshot.elapsed), unit: "")
                HalsynWatchMetric(title: "Ritmo medio", systemImage: "speedometer", value: snapshot.averagePace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol)
                HalsynWatchMetric(title: "FC media", systemImage: "heart", value: snapshot.averageHeartRate.map { HalsynFormat.integer($0) }, unit: "lpm")
                HalsynWatchMetric(title: "FC máx. registrada", systemImage: "heart.fill", value: snapshot.maxHeartRate.map { HalsynFormat.integer($0) }, unit: "lpm")
                if !snapshot.laps.isEmpty {
                    HalsynWatchMetric(title: "Vueltas", systemImage: "flag", value: "\(snapshot.laps.count)", unit: "")
                }
                if snapshot.zoneSeconds.reduce(0, +) > 0 {
                    ZoneBarsView(seconds: snapshot.zoneSeconds)
                }
                Button("Hecho") { workout.dismissSummary() }
                    .tint(Color(HalsynPalette.darkAccent))
                    .padding(.top, 4)
            }
        }
    }
}

/// Tiempo en cada zona (Z1–Z5) como barras horizontales.
private struct ZoneBarsView: View {
    let seconds: [TimeInterval]

    var body: some View {
        let total = max(seconds.reduce(0, +), 1)
        VStack(alignment: .leading, spacing: 3) {
            Text("Tiempo en zonas")
                .font(.caption2)
                .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            ForEach(1..<min(seconds.count, 6), id: \.self) { zone in
                HStack(spacing: 4) {
                    Text(verbatim: "Z\(zone)").font(.caption2.monospacedDigit()).frame(width: 22, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color(HalsynPalette.alertDark).opacity(0.35 + 0.13 * Double(zone)))
                            .frame(width: max(2, proxy.size.width * seconds[zone] / total))
                    }
                    .frame(height: 6)
                    Text(verbatim: HalsynFormat.duration(seconds[zone])).font(.caption2.monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
