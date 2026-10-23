import CoreLocation
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
        NavigationStack {
            if workout.outcome != nil || workout.phase == .ended {
                WorkoutSummaryView()
                    // "Hecho" en lugar de la cruz del sistema.
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Hecho") { workout.dismissSummary() }
                        }
                    }
            } else if workout.phase == .preparing {
                Group {
                    if let countdown = workout.countdown {
                        CountdownView(value: countdown)
                    } else {
                        VStack(spacing: 8) {
                            HalsynSymbol().frame(height: 44)
                            ProgressView()
                            Text("Preparando…").font(.footnote)
                        }
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            } else {
                // Durante la carrera no hay cruz: se termina desde los controles.
                WorkoutPagesView()
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .interactiveDismissDisabled(workout.isActive)
    }
}

/// 3, 2, 1 en grande, con un anillo que se cierra en cada segundo.
private struct CountdownView: View {
    let value: Int
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Circle()
                .stroke(Color(HalsynPalette.darkAccent).opacity(0.2), lineWidth: 8)
                .padding(14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color(HalsynPalette.darkAccent), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(14)
            Text(verbatim: "\(value)")
                .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white)
                .contentTransition(.numericText(countsDown: true))
                .id(value)
                .transition(.scale(scale: 1.4).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: value)
        .onAppear { fill() }
        .onChange(of: value) { _, _ in fill() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(value)"))
    }

    private func fill() {
        progress = 0
        withAnimation(.linear(duration: 0.95)) { progress = 1 }
    }
}

/// Doble toque (Apple Watch Series 9, Ultra 2 o posterior, watchOS 11) activa el botón.
private struct PrimaryActionShortcut: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 11.0, *) {
            content.handGestureShortcut(.primaryAction)
        } else {
            content
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

/// Botón pequeño de pausa en las métricas. Con doble toque también pausa.
private struct PauseButton: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        if workout.phase == .running {
            Button {
                workout.togglePause()
            } label: {
                Image(systemName: "pause.fill")
                    .font(.footnote.weight(.bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(HalsynPalette.cautionDark).opacity(0.25)))
                    .foregroundStyle(Color(HalsynPalette.cautionDark))
            }
            .buttonStyle(.plain)
            .modifier(PrimaryActionShortcut())
            .accessibilityLabel(Text("Pausa"))
        }
    }
}

/// En pausa: reanudar (también con doble toque) o terminar.
private struct PausedPanel: View {
    @Environment(WorkoutManager.self) private var workout
    @State private var confirmingEnd = false

    var body: some View {
        VStack(spacing: 8) {
            PausedLabel()
            Button {
                workout.togglePause()
            } label: {
                Label("Reanudar", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(Color(HalsynPalette.darkAccent))
            .modifier(PrimaryActionShortcut())
            Button(role: .destructive) {
                confirmingEnd = true
            } label: {
                Label("Terminar", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(Color(HalsynPalette.alertDark))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.88)))
        .confirmationDialog("¿Terminar el entrenamiento?", isPresented: $confirmingEnd) {
            Button("Guardar en Apple Health") { workout.end(save: true) }
            Button("Descartar", role: .destructive) { workout.end(save: false) }
            Button("Seguir", role: .cancel) {}
        }
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
            VStack(alignment: .center, spacing: 2) {
                HStack {
                    if let zone = snapshot.heartRateZone, workout.phase != .paused {
                        HalsynZoneGauge(zone: zone)
                    } else {
                        Spacer()
                    }
                    PauseButton()
                }
                HalsynWorkoutScreen(profile: profile) { snapshot.value(for: $0, unit: unitSystem) }
            }
            .padding(.horizontal, 4)
            .overlay(alignment: .top) {
                BannerOverlay(banner: workout.banner, now: context.date)
            }
            .overlay {
                if workout.phase == .paused {
                    PausedPanel()
                }
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
                unit: unitSystem,
                zones: RunSettingsStore.shared.settings.zones.zones
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

    /// Ruta reducida a como mucho 300 puntos: dibujar miles de puntos por segundo traba el reloj.
    private var route: [CLLocationCoordinate2D] {
        let all = workout.routeCoordinates
        guard all.count > 300 else { return all }
        let step = Int((Double(all.count) / 300).rounded(.up))
        var reduced = stride(from: 0, to: all.count, by: step).map { all[$0] }
        if let last = all.last { reduced.append(last) }
        return reduced
    }

    var body: some View {
        // Sin gestos en el mapa: si el mapa se mueve con el dedo, no se puede
        // deslizar a las otras páginas (controles para pausar o terminar).
        Map(position: $position, interactionModes: []) {
            if route.count > 1 {
                MapPolyline(coordinates: route)
                    .stroke(Color(HalsynPalette.darkAccent), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            UserAnnotation()
        }
        .allowsHitTesting(false)
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
            controlButton("Terminar", systemImage: "stop.fill", tint: Color(HalsynPalette.alertDark)) {
                confirmingEnd = true
            }
        }
        .confirmationDialog("¿Terminar el entrenamiento?", isPresented: $confirmingEnd) {
            Button("Guardar en Apple Health") { workout.end(save: true) }
            Button("Descartar", role: .destructive) { workout.end(save: false) }
            Button("Seguir", role: .cancel) {}
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

/// Resumen al terminar: distancia grande, tiempo y ritmo, mapa, ritmo dibujado y zonas.
private struct WorkoutSummaryView: View {
    @Environment(WorkoutManager.self) private var workout

    /// Ruta reducida para el mapa del resumen.
    private var route: [CLLocationCoordinate2D] {
        let all = workout.routeCoordinates
        guard all.count > 300 else { return all }
        let step = Int((Double(all.count) / 300).rounded(.up))
        var reduced = stride(from: 0, to: all.count, by: step).map { all[$0] }
        if let last = all.last { reduced.append(last) }
        return reduced
    }

    var body: some View {
        let snapshot = workout.snapshot(at: .now)
        ScrollView {
            VStack(spacing: 10) {
                outcome
                Label(workout.isWalking ? LocalizedStringKey("Caminata") : LocalizedStringKey("Carrera"), systemImage: workout.isWalking ? "figure.walk" : "figure.run")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                if let name = snapshot.intervalPlanName {
                    Text(verbatim: name)
                        .font(.headline)
                        .foregroundStyle(Color(HalsynPalette.darkAccent))
                }
                HalsynWorkoutField(label: "DISTANCIA", value: HalsynFormat.distance(meters: snapshot.distance, unit: unitSystem), unit: unitSystem.distanceUnitSymbol, size: .large, alignment: .center)
                HStack {
                    HalsynWorkoutField(label: "TID", value: HalsynFormat.duration(snapshot.elapsed), unit: "", size: .small, alignment: .center)
                    HalsynWorkoutField(label: "RITMO", value: snapshot.averagePace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol, size: .small, alignment: .center)
                }
                if route.count > 1 {
                    Map(initialPosition: .automatic, interactionModes: []) {
                        MapPolyline(coordinates: route)
                            .stroke(Color(HalsynPalette.darkAccent), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        if let first = route.first {
                            Annotation("", coordinate: first) { Circle().fill(Color(HalsynPalette.positiveDark)).frame(width: 8, height: 8) }
                        }
                        if let last = route.last {
                            Annotation("", coordinate: last) { Circle().fill(Color(HalsynPalette.alertDark)).frame(width: 8, height: 8) }
                        }
                    }
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .allowsHitTesting(false)
                    .accessibilityLabel(Text("Mapa de la ruta"))
                }
                if snapshot.paceSamples.count > 3 {
                    HalsynLiveRunChart(
                        paceSamples: snapshot.paceSamples,
                        heartRateSamples: snapshot.heartRateSamples,
                        averagePace: snapshot.averagePace,
                        currentPace: nil,
                        heartRate: nil,
                        paceTarget: nil,
                        unit: unitSystem,
                        zones: RunSettingsStore.shared.settings.zones.zones
                    )
                    .frame(height: 130)
                }
                HStack {
                    HalsynWorkoutField(label: "PULS", value: snapshot.averageHeartRate.map { HalsynFormat.integer($0) }, unit: "lpm", size: .small, emphasis: Color(HalsynPalette.alertDark), alignment: .center)
                    HalsynWorkoutField(label: "MÁX.", value: snapshot.maxHeartRate.map { HalsynFormat.integer($0) }, unit: "lpm", size: .small, emphasis: Color(HalsynPalette.alertDark), alignment: .center)
                }
                if !snapshot.laps.isEmpty {
                    HalsynWatchMetric(title: "Vueltas", systemImage: "flag", value: "\(snapshot.laps.count)", unit: "")
                }
                if snapshot.zoneSeconds.reduce(0, +) > 0 {
                    ZoneBarsView(seconds: snapshot.zoneSeconds)
                }
                Button {
                    workout.dismissSummary()
                } label: {
                    Text("Hecho").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(HalsynPalette.darkAccent))
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch workout.outcome {
        case .saved:
            Label("Guardada en Apple Health", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color(HalsynPalette.darkAccent))
        case .discarded:
            Label("Carrera descartada", systemImage: "trash")
                .font(.footnote)
                .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
        case .failed:
            Label("No se pudo completar", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Color(HalsynPalette.cautionDark))
            if let message = workout.errorMessage {
                Text(verbatim: message).font(.caption2)
            }
        case nil:
            ProgressView()
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
