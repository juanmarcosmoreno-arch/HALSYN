import HalsynCore
import HalsynDesign
import SwiftUI

/// Pantalla de carrera: controles · métricas · vueltas (deslizando en horizontal).
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

private struct WorkoutPagesView: View {
    enum Page { case controls, metrics, laps }

    @Environment(WorkoutManager.self) private var workout
    @State private var page: Page = .metrics

    var body: some View {
        TabView(selection: $page) {
            WorkoutControlsView().tag(Page.controls)
            WorkoutMetricsView().tag(Page.metrics)
            WorkoutLapsView().tag(Page.laps)
        }
        .tabViewStyle(.page)
        .onChange(of: workout.phase) { _, phase in
            // Al pausar o reanudar se vuelve a las métricas.
            if phase == .running || phase == .paused {
                withAnimation { page = .metrics }
            }
        }
    }
}

/// Métricas en vivo con el perfil de pantalla (Easy Run por ahora; el editor llega en la Fase 5).
private struct WorkoutMetricsView: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @AppStorage("halsyn.watch.unitSystem") private var unitSystem: UnitSystem = .metric

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 1 : 0.5)) { context in
            let snapshot = workout.snapshot(at: context.date)
            VStack(alignment: .leading, spacing: 2) {
                if workout.phase == .paused {
                    Label("En pausa", systemImage: "pause.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(HalsynPalette.cautionDark))
                }
                HalsynWorkoutScreen(profile: .easyRun) { snapshot.value(for: $0, unit: unitSystem) }
            }
            .padding(.horizontal, 4)
        }
        .background(Color.black.ignoresSafeArea())
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
    @AppStorage("halsyn.watch.unitSystem") private var unitSystem: UnitSystem = .metric

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
    @AppStorage("halsyn.watch.unitSystem") private var unitSystem: UnitSystem = .metric

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
                HalsynWatchMetric(title: "Distancia", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: HalsynFormat.distance(meters: snapshot.distance, unit: unitSystem), unit: unitSystem.distanceUnitSymbol)
                HalsynWatchMetric(title: "Tiempo", systemImage: "stopwatch", value: HalsynFormat.duration(snapshot.elapsed), unit: "")
                HalsynWatchMetric(title: "Ritmo medio", systemImage: "speedometer", value: snapshot.averagePace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol)
                HalsynWatchMetric(title: "FC media", systemImage: "heart", value: snapshot.averageHeartRate.map { HalsynFormat.integer($0) }, unit: "lpm")
                HalsynWatchMetric(title: "FC máx. registrada", systemImage: "heart.fill", value: snapshot.maxHeartRate.map { HalsynFormat.integer($0) }, unit: "lpm")
                if !snapshot.laps.isEmpty {
                    HalsynWatchMetric(title: "Vueltas", systemImage: "flag", value: "\(snapshot.laps.count)", unit: "")
                }
                Button("Hecho") { workout.dismissSummary() }
                    .tint(Color(HalsynPalette.darkAccent))
                    .padding(.top, 4)
            }
        }
    }
}
