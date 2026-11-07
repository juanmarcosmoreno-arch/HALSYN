import HalsynCore
import HalsynDesign
import HealthKit
import SwiftUI

/// SPRING — running. Las carreras se registran en el Apple Watch; aquí se ven
/// las estadísticas, el plan, las zapatillas, la predicción y el historial. Los
/// ajustes del reloj (pantallas, zonas, alertas, intervalos, voz) están en el
/// engranaje de la tarjeta de inicio.
struct SpringView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var workouts: [WorkoutSummary]?
    @State private var predictions: [RacePrediction] = []
    /// Modelo de rendimiento (si hay pruebas): forma, tendencia y confianza.
    @State private var performance: PerformanceAssessment?
    /// Sin duplicados ni lo que excluiste (control de calidad).
    @State private var allWorkouts: [WorkoutSummary] = []
    /// Todo lo que vino de Salud, para revisar la calidad.
    @State private var rawWorkouts: [WorkoutSummary] = []
    @State private var flaggedCount = 0
    @AppStorage(FitnessStore.riegelExponentKey) private var riegelExponent = RacePerformanceModel.defaultRiegelExponent
    @State private var showsStartInfo = false

    var body: some View {
        NavigationStack {
            HalsynScreen {
                ModuleHeader(module: .spring, isDemo: model.isDemo)
                    .padding(.top, HalsynSpacing.s)
                startCard
                if let workouts {
                    // Arriba, lo de hoy: el plan y con qué zapatillas.
                    TrainingPlanCard(workouts: allWorkouts)
                    ShoesCard(workouts: allWorkouts)
                    StrengthCard()
                    EvolutionCard(runs: allWorkouts)
                    AnalysisSection("spring") {
                        RunningStatsCard(workouts: allWorkouts)
                        TrainingLoadCard()
                        HeartRateRecoveryCard()
                        RacePredictionCard(predictions: predictions, performance: performance, runs: allWorkouts, unitSystem: unitSystem)
                    }
                    if flaggedCount > 0 {
                        NavigationLink {
                            DataQualityView(workouts: rawWorkouts)
                        } label: {
                            HalsynCard {
                                HStack {
                                    Label("Calidad de los datos: \(String(flaggedCount)) para revisar", systemImage: "checkmark.shield")
                                        .font(.halsynCaption.weight(.semibold))
                                        .foregroundStyle(.halsynPrimaryText)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.halsynSecondaryText)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
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
                // Suficientes para las estadísticas del año y los récords.
                let recent = await model.provider.recentWorkouts(limit: 400)
                refresh(recent)
            }
            .onChange(of: WorkoutQualityStore.shared.excluded) { _, _ in refresh(rawWorkouts) }
            .onChange(of: WorkoutQualityStore.shared.included) { _, _ in refresh(rawWorkouts) }
            .onChange(of: riegelExponent) { _, _ in refresh(rawWorkouts) }
            .sheet(isPresented: $showsStartInfo) {
                StartRunInfoSheet()
                    .presentationDetents([.medium])
            }
        }
    }

    /// Los cálculos (plan, forma, predicción, estadísticas) usan los datos
    /// limpios; el historial muestra todo.
    private func refresh(_ recent: [WorkoutSummary]) {
        rawWorkouts = recent
        let clean = WorkoutQualityStore.shared.clean(recent)
        allWorkouts = clean
        workouts = Array(recent.prefix(20))
        // Con pruebas (tests, competiciones o esfuerzos a tope), el modelo de
        // rendimiento; si no, Riegel con tus mejores carreras.
        performance = FitnessStore.shared.performance(runs: clean)
        predictions = performance.map(RacePrediction.from) ?? RacePredictor.predictions(from: clean, endingOn: .now, calendar: .current)
        flaggedCount = DataQuality.assess(recent).values.filter(\.needsReview).count
    }

    private var startCard: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Carrera libre")
                        .font(.halsynTitle)
                        .foregroundStyle(.halsynPrimaryText)
                    Spacer()
                    NavigationLink {
                        RunSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(.halsynAccentText)
                    }
                    .accessibilityLabel(Text("Ajustes de carrera"))
                }
                Text("Tiempo, distancia, ritmo y frecuencia cardíaca en directo desde tu Apple Watch, incluso sin el iPhone.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                HalsynPrimaryButton("Correr con Apple Watch", systemImage: "applewatch") {
                    showsStartInfo = true
                }
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
                HalsynStatusIndicator(.positive, text: "Mira tu Apple Watch: el entrenamiento está empezando.")
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
                    Task { await start(walking: false) }
                }
                .disabled(status == .starting)
                Button {
                    Task { await start(walking: true) }
                } label: {
                    Label("Iniciar caminata", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.halsynAccent)
                .disabled(status == .starting)
            }
        }
        .padding(HalsynSpacing.l)
        .halsynScreenBackground()
    }

    private func start(walking: Bool) async {
        status = .starting
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = walking ? .walking : .running
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
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(workout.activity.title))
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    PerformanceMarkBadge(workoutID: workout.id)
                }
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
                RunWeatherBadge(workout: workout, unitSystem: unitSystem)
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

/// Acceso fijo a los ejercicios de gimnasio para corredores (antes solo
/// aparecía los días de gimnasio del plan).
struct StrengthCard: View {
    var body: some View {
        NavigationLink {
            RunnerStrengthView()
        } label: {
            HalsynCard {
                HStack(spacing: HalsynSpacing.m) {
                    Image(systemName: "figure.strengthtraining.functional")
                        .font(.title2)
                        .foregroundStyle(.halsynAccentText)
                        .frame(width: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gimnasio")
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                        Text("Ejercicios de fuerza para corredores")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.halsynSecondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
