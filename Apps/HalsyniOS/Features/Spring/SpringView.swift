import HalsynCore
import HalsynDesign
import HealthKit
import SwiftUI

/// SPRING — running. Las carreras se registran en el Apple Watch (Fase 4);
/// aquí se ven el historial y el resumen semanal, y se configuran pantallas,
/// zonas, alertas e intervalos (Fase 5), que se envían al reloj.
struct SpringView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var workouts: [WorkoutSummary]?
    @State private var showsStartInfo = false
    private var runSettings: RunSettings { RunSettingsStore.shared.settings }

    var body: some View {
        NavigationStack {
            HalsynScreen {
                ModuleHeader(module: .spring, isDemo: model.isDemo)
                    .padding(.top, HalsynSpacing.s)
                startCard
                settingsCard
                if let workouts {
                    weeklySummary(workouts)
                    history(workouts)
                } else {
                    HalsynLoadingState()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WorkoutSummary.self) { workout in
                WorkoutDetailView(workout: workout)
            }
            .task(id: model.reloadKey) {
                workouts = await model.provider.recentWorkouts(limit: 20)
            }
            .sheet(isPresented: $showsStartInfo) {
                StartRunInfoSheet()
                    .presentationDetents([.medium])
            }
        }
    }

    private var startCard: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                Text("Carrera libre")
                    .font(.halsynTitle)
                    .foregroundStyle(.halsynPrimaryText)
                Text("Tiempo, distancia, ritmo y frecuencia cardíaca en directo desde tu Apple Watch, incluso sin el iPhone.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                HalsynPrimaryButton("Correr con Apple Watch", systemImage: "applewatch") {
                    showsStartInfo = true
                }
            }
        }
    }

    /// Pantallas configuradas y acceso a los ajustes de carrera.
    private var settingsCard: some View {
        NavigationLink {
            RunSettingsView()
        } label: {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                    HStack {
                        HalsynSectionHeader("Ajustes de carrera", eyebrow: HalsynLexicon.form.rawValue)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.halsynSecondaryText)
                            .accessibilityHidden(true)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: HalsynSpacing.s) {
                            ForEach(runSettings.validScreens) { profile in
                                WatchScreenPreview(profile: profile)
                                    .frame(width: 96)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
                        settingRow("heart", zonesText)
                        settingRow("bell.badge", alertsText)
                        settingRow("repeat", "\(runSettings.intervalPlans.count) planes de intervalos")
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func settingRow(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: systemImage)
            .font(.halsynCaption)
            .foregroundStyle(.halsynSecondaryText)
    }

    private var zonesText: LocalizedStringKey {
        guard let max = runSettings.zones.zones.last?.upperBound else { return "Zonas cardíacas sin configurar" }
        return "Zonas con FC máx. \(Int(max)) lpm"
    }

    private var alertsText: LocalizedStringKey {
        switch (runSettings.alerts.paceEnabled, runSettings.alerts.zoneEnabled) {
        case (true, true): "Alertas de ritmo y zona activas"
        case (true, false): "Alerta de ritmo activa"
        case (false, true): "Alerta de zona activa"
        case (false, false): "Sin alertas"
        }
    }

    private func weeklySummary(_ workouts: [WorkoutSummary]) -> some View {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let thisWeek = workouts.filter { $0.start >= weekStart }
        let distance = thisWeek.compactMap(\.distanceMeters).reduce(0, +)
        let duration = thisWeek.map(\.duration).reduce(0, +)
        return HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Esta semana", eyebrow: HalsynLexicon.rorelse.rawValue)
                HStack {
                    HalsynMetric(title: "Distancia", value: HalsynFormat.distance(meters: distance, unit: unitSystem), unit: unitSystem.distanceUnitSymbol)
                    Spacer()
                    HalsynMetric(title: "Carreras", value: String(thisWeek.count), unit: "")
                    Spacer()
                    HalsynMetric(title: "Ritmo medio", value: Pace(distanceMeters: distance, duration: duration)?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol)
                }
                DataOriginFootnote(origin: thisWeek.first?.origin)
            }
        }
    }

    @ViewBuilder
    private func history(_ workouts: [WorkoutSummary]) -> some View {
        HalsynSectionHeader("Historial", eyebrow: HalsynLexicon.tid.rawValue)
        if workouts.isEmpty {
            HalsynEmptyState(systemImage: "figure.run", title: "Sin carreras todavía", message: "Tus entrenamientos aparecerán aquí.")
        } else {
            VStack(spacing: HalsynSpacing.s) {
                ForEach(workouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutRow(workout: workout, unitSystem: unitSystem)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Inicia una carrera en el Apple Watch desde el iPhone (`startWatchApp`):
/// watchOS abre HÅLSYN en el reloj con la sesión preparada.
private struct StartRunInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle, starting, started, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            HalsynSymbol().frame(height: 40)
            Text("Correr con Apple Watch")
                .font(.halsynTitle)
                .foregroundStyle(.halsynPrimaryText)
            Text("La carrera se registra en el reloj, incluso si dejas el iPhone en casa. Puedes iniciarla desde aquí o tocando SPRING en el reloj.")
                .font(.halsynBody)
                .foregroundStyle(.halsynSecondaryText)
            switch status {
            case .started:
                HalsynStatusIndicator(.positive, text: "Mira tu Apple Watch: la carrera está empezando.")
            case .failed:
                HalsynStatusIndicator(.caution, text: "No se pudo abrir HÅLSYN en el reloj. Comprueba que está instalada y que el reloj está desbloqueado.")
            default:
                EmptyView()
            }
            Spacer()
            if status == .started {
                HalsynPrimaryButton("Entendido") { dismiss() }
            } else {
                HalsynPrimaryButton(status == .starting ? "Abriendo el reloj…" : "Iniciar carrera al aire libre", systemImage: "applewatch") {
                    Task { await start() }
                }
                .disabled(status == .starting)
            }
        }
        .padding(HalsynSpacing.l)
        .halsynScreenBackground()
    }

    private func start() async {
        status = .starting
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                HKHealthStore().startWatchApp(with: configuration) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: CancellationError())
                    }
                }
            }
            status = .started
        } catch {
            status = .failed
        }
    }
}

struct WorkoutRow: View {
    let workout: WorkoutSummary
    let unitSystem: UnitSystem

    var body: some View {
        HStack(spacing: HalsynSpacing.m) {
            Image(systemName: workout.activity.systemImage)
                .font(.title3)
                .foregroundStyle(.halsynAccent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.halsynAccentSoft.opacity(0.35)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(workout.activity.title))
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                Text(workout.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "\(workout.distanceMeters.map { HalsynFormat.distance(meters: $0, unit: unitSystem) } ?? "—") \(unitSystem.distanceUnitSymbol)")
                    .font(.halsynHeadline.monospacedDigit())
                    .foregroundStyle(.halsynPrimaryText)
                Text(verbatim: "\(workout.averagePace?.formatted(in: unitSystem) ?? "—") \(unitSystem.paceUnitSymbol)")
                    .font(.halsynCaption.monospacedDigit())
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .padding(HalsynSpacing.m)
        .background(RoundedRectangle(cornerRadius: HalsynRadius.tile, style: .continuous).fill(Color.halsynSurface))
        .overlay(RoundedRectangle(cornerRadius: HalsynRadius.tile, style: .continuous).strokeBorder(Color.halsynHairline, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SpringView()
        .environment(AppModel())
}
