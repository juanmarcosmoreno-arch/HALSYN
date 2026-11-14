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
            if workout.warmup.isActive {
                WarmupView()
                    .toolbar(.hidden, for: .navigationBar)
            } else if workout.recoveryMeter.isActive {
                // Recuperación del pulso: antes del resumen de la carrera.
                RecoveryView()
                    .toolbar(.hidden, for: .navigationBar)
            } else if workout.outcome != nil || workout.phase == .ended {
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
        case controls, interval, intervalDetail, screen(Int), chart, map, laps
    }

    @Environment(WorkoutManager.self) private var workout
    @State private var page: Page = .screen(0)

    var body: some View {
        TabView(selection: $page) {
            WorkoutControlsView().tag(Page.controls)
            if workout.isCycling {
                // CYKEL: velocidad y pulso; después potencia, cadencia y desnivel.
                RideMetricsView(page: .main).tag(Page.screen(0))
                RideMetricsView(page: .sensors).tag(Page.screen(1))
                if !workout.isIndoor {
                    WorkoutMapView().tag(Page.map)
                }
                WorkoutLapsView().tag(Page.laps)
            } else {
                runPages
            }
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

    @ViewBuilder
    private var runPages: some View {
        if workout.plan != nil {
            // Primero el anillo que se vacía con lo que falta; después el detalle.
            WorkoutIntervalRingView().tag(Page.interval)
            WorkoutIntervalView().tag(Page.intervalDetail)
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

/// En pausa: distancia y ritmo medio (velocidad media en bici) hasta ahora.
private struct PausedSummary: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        let snapshot = workout.snapshot(at: .now)
        HStack(spacing: 4) {
            HalsynWorkoutField(label: "DISTANCIA", value: HalsynFormat.distance(meters: snapshot.distance, unit: unitSystem), unit: unitSystem.distanceUnitSymbol, size: .small, alignment: .center)
            if workout.isCycling {
                HalsynWorkoutField(label: "VEL. MEDIA", value: Speed(pace: snapshot.averagePace)?.formatted(in: unitSystem), unit: unitSystem.speedUnitSymbol, size: .small, alignment: .center)
            } else {
                HalsynWorkoutField(label: "RITMO MEDIO", value: snapshot.averagePace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol, size: .small, alignment: .center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// En pausa: distancia y ritmo medio, y reanudar (también con doble toque) o terminar.
private struct PausedPanel: View {
    @Environment(WorkoutManager.self) private var workout
    @State private var confirmingEnd = false

    var body: some View {
        VStack(spacing: 8) {
            PausedLabel()
            PausedSummary()
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
            if workout.offersRecovery {
                Button("Guardar y medir recuperación") { workout.end(save: true, measureRecovery: true) }
            }
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

/// Métricas de una salida en bici. Potencia y cadencia solo con sensores
/// Bluetooth emparejados; sin ellos se muestran vacías ("--"), nunca estimadas.
private struct RideMetricsView: View {
    enum Page { case main, sensors }

    let page: Page
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
                VStack(spacing: 0) {
                    switch page {
                    case .main:
                        HalsynWorkoutField(label: "TID", value: HalsynFormat.duration(snapshot.elapsed), unit: "", size: .large, alignment: .center)
                        Spacer(minLength: 2)
                        HalsynWorkoutField(label: "VELOCIDAD", value: Speed(pace: snapshot.currentPace)?.formatted(in: unitSystem), unit: unitSystem.speedUnitSymbol, size: .medium, alignment: .center)
                        Spacer(minLength: 2)
                        HalsynWorkoutField(label: "DISTANCIA", value: HalsynFormat.distance(meters: snapshot.distance, unit: unitSystem), unit: unitSystem.distanceUnitSymbol, size: .medium, alignment: .center)
                        Spacer(minLength: 2)
                        HalsynWorkoutField(label: "PULS", value: snapshot.heartRate.map { HalsynFormat.integer($0) }, unit: "lpm", size: .medium, emphasis: Color(HalsynPalette.alertDark), alignment: .center)
                    case .sensors:
                        HalsynWorkoutField(label: powerLabel(snapshot.powerZone), value: snapshot.power.map { HalsynFormat.integer($0) }, unit: "W", size: .large, alignment: .center)
                        Spacer(minLength: 2)
                        HalsynWorkoutField(label: "CADENCIA", value: snapshot.cadence.map { HalsynFormat.integer($0) }, unit: "rpm", size: .medium, alignment: .center)
                        Spacer(minLength: 2)
                        HalsynWorkoutField(label: "VEL. MEDIA", value: Speed(pace: snapshot.averagePace)?.formatted(in: unitSystem), unit: unitSystem.speedUnitSymbol, size: .medium, alignment: .center)
                        Spacer(minLength: 2)
                        HalsynWorkoutField(label: "DESNIVEL", value: snapshot.elevationGain.map { HalsynFormat.integer($0) }, unit: "m", size: .medium, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

    /// "KRAFT · Z3": marca sueca y zona de potencia, no se traducen.
    private func powerLabel(_ zone: Int?) -> String {
        zone.map { "KRAFT · Z\($0)" } ?? "KRAFT" // nolocalize
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

/// Color de cada paso de los intervalos (el mismo en el anillo y en el detalle).
private func intervalTint(_ kind: IntervalStepKind) -> Color {
    switch kind {
    case .work: Color(HalsynPalette.alertDark)
    case .recovery: Color(HalsynPalette.darkAccent)
    case .warmup, .cooldown: Color(HalsynPalette.cautionDark)
    }
}

/// Color del anillo: el elegido en el iPhone o, «Según el tramo», el del paso.
@MainActor func ringTint(_ kind: IntervalStepKind) -> Color {
    RunSettingsStore.shared.settings.ringColor.rgb.map { Color($0) } ?? intervalTint(kind)
}

/// Paso actual en un anillo que se va vaciando con el tiempo o la distancia que
/// falta; en el centro, lo que queda. En pasos abiertos el anillo queda lleno.
private struct WorkoutIntervalRingView: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 1 : 0.5)) { context in
            let snapshot = workout.snapshot(at: context.date)
            Group {
                if let interval = snapshot.interval {
                    ring(interval, snapshot: snapshot)
                } else {
                    VStack(spacing: 4) {
                        Label(completedTitle(snapshot), systemImage: "checkmark.circle")
                            .font(.headline)
                            .foregroundStyle(Color(HalsynPalette.darkAccent))
                        HalsynWorkoutScreen(profile: workout.screens.first ?? .easyRun) { snapshot.value(for: $0, unit: unitSystem) }
                    }
                }
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func completedTitle(_ snapshot: RunSnapshot) -> LocalizedStringKey {
        guard snapshot.intervalsCompleted else { return "Carrera libre" }
        return workout.plan?.isGoalRun == true ? "Objetivo cumplido" : "Intervalos completados"
    }

    private func ring(_ interval: IntervalProgress, snapshot: RunSnapshot) -> some View {
        // El anillo se queda con todo el alto libre: encabezado y pie en una línea cada uno.
        VStack(spacing: 0) {
            // Debajo de la franja de la hora: el anillo no la toca.
            Color.clear.frame(height: 24)
            ringDial(interval, value: snapshot.value(for: .intervalTime, unit: unitSystem), tint: dialTint(interval, snapshot: snapshot), snapshot: snapshot)
                .overlay {
                    // El arco de ritmo acompaña al anillo por fuera, sin achicarlo.
                    if let target = interval.step.paceTarget {
                        PaceArcView(target: target, current: snapshot.currentPace, unit: unitSystem, tint: dialTint(interval, snapshot: snapshot))
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 5)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            ringFooter(snapshot, tint: dialTint(interval, snapshot: snapshot))
                // Más abajo, justo sobre los puntos de página, sin meterse en las esquinas.
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
        }
        // Usa también las franjas de arriba (la de la hora) y de abajo.
        .padding(.top, 2)
        .frame(maxHeight: .infinity)
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    /// Con ritmo objetivo el anillo dice cómo vas: verde en ritmo, rojo si vas
    /// más lento, amarillo si vas más rápido. Sin ritmo, el color elegido.
    private func dialTint(_ interval: IntervalProgress, snapshot: RunSnapshot) -> Color {
        guard let target = interval.step.paceTarget, let pace = snapshot.currentPace else {
            return ringTint(interval.step.kind)
        }
        switch target.status(of: pace) {
        case .slower: return Color(HalsynRGBColor(hex: 0xFF453A))
        case .onPace: return Color(HalsynPalette.darkAccent)
        case .faster: return Color(HalsynPalette.cautionDark)
        }
    }

    /// Ritmo actual dentro del anillo, arriba de lo que queda (solo con ritmo objetivo).
    private func currentPaceText(_ interval: IntervalProgress, snapshot: RunSnapshot) -> (text: String, color: Color)? {
        guard interval.step.paceTarget != nil else { return nil }
        let color = snapshot.currentPace == nil ? Color(HalsynPalette.secondaryTextDark) : dialTint(interval, snapshot: snapshot)
        return (snapshot.currentPace?.formatted(in: unitSystem) ?? "--", color)
    }

    private func ringDial(_ interval: IntervalProgress, value: WorkoutFieldValue, tint: Color, snapshot: RunSnapshot) -> some View {
        let isOpen = interval.step.goal == .open
        let remaining: Double = isOpen ? 1 : 1 - (interval.fraction ?? 0)
        return ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: 9)
            Circle()
                .trim(from: 0, to: remaining)
                .stroke(tint.opacity(isOpen && interval.step.paceTarget == nil ? 0.5 : 1), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: remaining)
            ringCenter(value: value, tint: tint, isOpen: isOpen, repetition: repetitionText(interval), pace: currentPaceText(interval, snapshot: snapshot))
                .padding(.horizontal, 12)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(workout.plan?.kind.title(for: interval.step.kind) ?? interval.step.kind.title)))
        .accessibilityValue(Text(verbatim: "\(value.value ?? "--") \(value.unit)"))
    }

    /// "2/5" solo si hay más de una repetición.
    private func repetitionText(_ interval: IntervalProgress) -> String? {
        guard let repetition = interval.step.repetition, let repeats = workout.plan?.repeats, repeats > 1 else { return nil }
        return "\(repetition)/\(repeats)"
    }

    private func ringCenter(value: WorkoutFieldValue, tint: Color, isOpen: Bool, repetition: String? = nil, pace: (text: String, color: Color)? = nil) -> some View {
        VStack(spacing: 0) {
            if let pace {
                // Tu ritmo actual, en el color del estado (verde en ritmo, rojo lento, amarillo rápido).
                Text(verbatim: pace.text)
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(pace.color)
                    .padding(.bottom, 2)
            }
            Text(isOpen ? LocalizedStringKey("TID") : LocalizedStringKey("QUEDAN"))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(tint)
            Text(verbatim: value.value ?? "--")
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(Color.white)
            if !value.unit.isEmpty {
                Text(LocalizedStringKey(value.unit))
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            }
            if let repetition {
                Text(verbatim: repetition)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .padding(.top, 1)
            }
            if isOpen, workout.plan?.isGoalRun != true {
                Text("Pulsa Vuelta para continuar")
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            }
        }
    }

    private func ringFooter(_ snapshot: RunSnapshot, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let target = snapshot.paceTarget, workout.isIndoor, !workout.isCycling {
                // En cinta: la velocidad a poner, con la inclinación elegida.
                let incline = TreadmillText.storedIncline
                compact(label: LocalizedStringKey(TreadmillText.percent(incline)), value: TreadmillText.speed(TreadmillEquivalent.speedRange(target, incline: incline), unit: unitSystem))
            } else if let target = snapshot.paceTarget {
                // Con ritmo objetivo, el ritmo actual va dentro del anillo.
                compact(label: "OBJETIVO", value: target.formatted(in: unitSystem))
            } else {
                compact(label: "RITMO", value: snapshot.currentPace.map { "\($0.formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol)" })
            }
            Spacer(minLength: 4)
            compact(label: "PULS", value: snapshot.heartRate.map { HalsynFormat.integer($0) })
        }
    }

    /// Etiqueta y valor en una sola línea, para dejarle el alto al anillo.
    private func compact(label: LocalizedStringKey, value: String?, tint: Color = .white) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                .fixedSize()
            Text(verbatim: value ?? "--")
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(tint)
        }
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
            Text(LocalizedStringKey(workout.plan?.kind.label(for: interval.step.kind) ?? interval.step.kind.label))
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
        intervalTint(kind)
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
            if workout.phase == .paused {
                PausedSummary()
            }
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
            if workout.offersRecovery {
                Button("Guardar y medir recuperación") { workout.end(save: true, measureRecovery: true) }
            }
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
                        Text(verbatim: workout.isCycling
                            ? "\(Speed(pace: lap.pace)?.formatted(in: unitSystem) ?? "--") \(unitSystem.speedUnitSymbol)"
                            : "\(lap.pace?.formatted(in: unitSystem) ?? "--") \(unitSystem.paceUnitSymbol)")
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
                if !workout.records.isEmpty {
                    RecordsSummary(records: workout.records, unit: unitSystem)
                }
                Label(activityTitle, systemImage: workout.isCycling ? (workout.isIndoor ? "figure.indoor.cycle" : "figure.outdoor.cycle") : (workout.isWalking ? "figure.walk" : "figure.run"))
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
                    if workout.isCycling {
                        HalsynWorkoutField(label: "VEL. MEDIA", value: Speed(pace: snapshot.averagePace)?.formatted(in: unitSystem), unit: unitSystem.speedUnitSymbol, size: .small, alignment: .center)
                    } else {
                        HalsynWorkoutField(label: "RITMO", value: snapshot.averagePace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol, size: .small, alignment: .center)
                    }
                }
                if workout.isCycling {
                    HStack {
                        HalsynWorkoutField(label: "KRAFT", value: snapshot.averagePower.map { HalsynFormat.integer($0) }, unit: "W", size: .small, alignment: .center)
                        HalsynWorkoutField(label: "DESNIVEL", value: snapshot.elevationGain.map { HalsynFormat.integer($0) }, unit: "m", size: .small, alignment: .center)
                    }
                    if let cadence = snapshot.averageCadence {
                        HalsynWorkoutField(label: "CADENCIA", value: HalsynFormat.integer(cadence), unit: "rpm", size: .small, alignment: .center)
                    }
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
                if snapshot.paceSamples.count > 3 && !workout.isCycling {
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

    private var activityTitle: LocalizedStringKey {
        if workout.isCycling { return "Bici" }
        return workout.isWalking ? "Caminata" : "Carrera"
    }

    @ViewBuilder
    private var outcome: some View {
        switch workout.outcome {
        case .saved:
            Label("Guardada en Apple Health", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color(HalsynPalette.darkAccent))
            if workout.recoverySkipped {
                Text("No había pulso en los últimos segundos: no se midió la recuperación.")
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.cautionDark))
            }
        case .discarded:
            Label(workout.isCycling ? LocalizedStringKey("Salida descartada") : LocalizedStringKey("Carrera descartada"), systemImage: "trash")
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
/// Récords de la carrera que terminó: 1.ª, 2.ª o 3.ª mejor de cada categoría.
private struct RecordsSummary: View {
    let records: [RunRecordPlacement]
    let unit: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(records.contains(where: \.isRecord) ? LocalizedStringKey("¡Récord personal!") : LocalizedStringKey("Entre tus mejores"), systemImage: "trophy.fill")
                .font(.headline)
                .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.13))
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: RunRecordWatchText.rank(record.rank) + " · " + String(localized: String.LocalizationValue(record.category.title)))  // nolocalize
                        .font(.caption2.weight(.semibold))
                    Text(verbatim: RunRecordWatchText.detail(record, unit: unit))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
    }
}

enum RunRecordWatchText {
    static func rank(_ rank: Int) -> String {
        switch rank {
        case 1: String(localized: "Récord")
        case 2: String(localized: "2.ª mejor")
        default: String(localized: "3.ª mejor")
        }
    }

    static func value(_ category: RunRecordCategory, _ value: Double, unit: UnitSystem) -> String {
        category == .longestDistance
            ? HalsynFormat.distance(meters: value, unit: unit) + " " + unit.distanceUnitSymbol  // nolocalize
            : HalsynFormat.duration(value)
    }

    static func detail(_ record: RunRecordPlacement, unit: UnitSystem) -> String {
        let valueText = value(record.category, record.value, unit: unit)
        guard record.isRecord, let previous = record.previousBest else { return valueText }
        let previousText = value(record.category, previous, unit: unit)
        return String(localized: "\(valueText) (antes \(previousText))")
    }
}

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
                    Text(verbatim: "Z\(zone)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(HalsynZoneColors.color(zone))
                        .frame(width: 22, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(HalsynZoneColors.color(zone))
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

/// Arco por fuera del anillo, de más de media vuelta: el punto blanco de
/// arriba es el ritmo objetivo y la rayita, tu ritmo actual (hacia la derecha
/// si vas más rápido, hacia la izquierda si vas más lento; ± 30 s/km en los
/// extremos), con el tramo del desvío en verde, rojo o amarillo. Se dibuja en
/// el mismo marco que el anillo, así que no le quita lugar.
struct PaceArcView: View {
    let target: PaceRange
    let current: Pace?
    let unit: UnitSystem
    let tint: Color

    /// Medio arco, en grados desde arriba (más de un cuarto de vuelta por lado
    /// para que el recorrido se note).
    static let halfSpan: Double = 105
    /// Distancia del arco al borde del anillo (el anillo mide 9 de grosor).
    static let gap: CGFloat = 10
    /// Lo que el lienzo sobresale del anillo por cada lado.
    static let inset: CGFloat = gap + 8

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let ringRadius: CGFloat = min(size.width, size.height) / 2 - Self.inset
            let radius: CGFloat = ringRadius + Self.gap
            var arc = Path()
            let steps = 40
            for step in 0...steps {
                let angle = -Self.halfSpan + 2 * Self.halfSpan * Double(step) / Double(steps)
                let p = point(angle, radius: radius, center: center)
                step == 0 ? arc.move(to: p) : arc.addLine(to: p)
            }
            context.stroke(arc, with: .color(Color.white.opacity(0.3)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            if let current {
                let angle = -target.deviation(of: current) * Self.halfSpan
                // Tramo desde el objetivo hasta tu ritmo, en el color del estado.
                var stretch = Path()
                for step in 0...20 {
                    let p = point(angle * Double(step) / 20, radius: radius, center: center)
                    step == 0 ? stretch.move(to: p) : stretch.addLine(to: p)
                }
                context.stroke(stretch, with: .color(tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            // Objetivo: punto blanco fijo arriba.
            let top = point(0, radius: radius, center: center)
            context.fill(Path(ellipseIn: CGRect(x: top.x - 3, y: top.y - 3, width: 6, height: 6)), with: .color(.white))
            // Ritmo actual: rayita que cruza el arco hacia el lado del desvío.
            if let current {
                let angle = -target.deviation(of: current) * Self.halfSpan
                var tick = Path()
                tick.move(to: point(angle, radius: radius - 5, center: center))
                tick.addLine(to: point(angle, radius: radius + 6, center: center))
                context.stroke(tick, with: .color(.black), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                context.stroke(tick, with: .color(tint), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        // El lienzo se agranda para que el arco quepa por fuera del anillo.
        .padding(-Self.inset)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Ritmo actual"))
        .accessibilityValue(Text(verbatim: current.map { $0.formatted(in: unit) } ?? "--"))
    }

    /// Punto a `degrees` desde arriba (positivo hacia la derecha, que es más rápido) a `radius` del centro.
    private func point(_ degrees: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let radians = CGFloat(degrees * .pi / 180)
        let x: CGFloat = center.x + radius * sin(radians)
        let y: CGFloat = center.y - radius * cos(radians)
        return CGPoint(x: x, y: y)
    }
}
