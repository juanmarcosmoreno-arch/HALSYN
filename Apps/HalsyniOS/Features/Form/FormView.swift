import HalsynCore
import HalsynDesign
import SwiftUI

/// FORM — rendimiento: si estás mejorando. Arriba lo que se ve de un vistazo
/// (predicción y evolución); debajo, cada área abre su detalle. Usa las mismas
/// tarjetas que antes estaban en SPRING: cambia el lugar, no los cálculos.
struct FormView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @AppStorage(FitnessStore.riegelExponentKey) private var riegelExponent = RacePerformanceModel.defaultRiegelExponent
    @State private var loaded = false
    @State private var runs: [WorkoutSummary] = []
    @State private var rawWorkouts: [WorkoutSummary] = []
    @State private var predictions: [RacePrediction] = []
    @State private var performance: PerformanceAssessment?
    @State private var flaggedCount = 0
    @State private var status: TrainingStatus?

    var body: some View {
        NavigationStack {
            HalsynScreen {
                if loaded {
                    FormOverview(isDemo: model.isDemo, predictions: predictions, performance: performance, runs: runs, rawWorkouts: rawWorkouts, flaggedCount: flaggedCount, unitSystem: unitSystem, status: status)
                } else {
                    ModuleHeader(module: .form, isDemo: model.isDemo)
                        .padding(.top, HalsynSpacing.s)
                    HalsynLoadingState()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: model.reloadKey) {
                let recent = await model.provider.recentWorkouts(limit: 400)
                refresh(recent)
                // Récords y análisis aeróbico (no en demo: los datos de ejemplo no son tuyos).
                if !model.isDemo {
                    await RunRecordStore.shared.refresh(runs: recent, provider: model.provider)
                    await AerobicStore.shared.refresh(runs: recent, provider: model.provider)
                }
                // Estado de entrenamiento con todo lo anterior ya calculado.
                status = await TrainingStatusBuilder.build(runs: runs, provider: model.provider, reloadKey: "\(model.reloadKey)")
            }
            .onChange(of: WorkoutQualityStore.shared.excluded) { _, _ in refresh(rawWorkouts) }
            .onChange(of: WorkoutQualityStore.shared.included) { _, _ in refresh(rawWorkouts) }
            .onChange(of: riegelExponent) { _, _ in refresh(rawWorkouts) }
        }
    }

    /// Los mismos datos limpios que usaba SPRING (sin duplicados ni lo que excluiste).
    private func refresh(_ recent: [WorkoutSummary]) {
        rawWorkouts = recent
        let clean = WorkoutQualityStore.shared.clean(recent)
        runs = clean
        IntensityContext.history = clean.filter(\.activity.isRun)
        performance = FitnessStore.shared.performance(runs: clean)
        let calibration = FitnessStore.shared.backtest(runs: clean).calibratedRelativeError
        predictions = performance.map { RacePrediction.from($0, calibratedRelativeError: calibration) } ?? RacePredictor.predictions(from: clean, endingOn: .now, calendar: .current)
        flaggedCount = DataQuality.assess(recent).values.filter(\.needsReview).count
        loaded = true
    }
}

/// Contenido de Rendimiento (separado para poder capturarlo en las pruebas).
struct FormOverview: View {
    let isDemo: Bool
    let predictions: [RacePrediction]
    let performance: PerformanceAssessment?
    let runs: [WorkoutSummary]
    let rawWorkouts: [WorkoutSummary]
    let flaggedCount: Int
    let unitSystem: UnitSystem
    var status: TrainingStatus? = nil

    var body: some View {
        ModuleHeader(module: .form, isDemo: isDemo)
            .padding(.top, HalsynSpacing.s)
        if let status {
            TrainingStatusCard(status: status)
        }
        // Nivel 1: de un vistazo.
        RacePredictionCard(predictions: predictions, performance: performance, runs: runs, unitSystem: unitSystem)
        EvolutionCard(runs: runs)

        // Nivel 2: cada área abre su detalle.
        HalsynSectionHeader("Áreas", eyebrow: HalsynLexicon.form.rawValue)
        AerobicAreaLink()
        ConsistencyAreaLink(runs: runs)
        RunningDynamicsAreaLink(runs: runs)
        FormAreaLink(title: "Carga y forma", subtitle: "Carga reciente frente a la habitual, forma y fatiga", systemImage: "gauge.with.dots.needle.50percent") {
            FormAreaScreen(title: "Carga y forma") { TrainingLoadCard() }
        }
        FormAreaLink(title: "Volumen e intensidad", subtitle: "Kilómetros por semana y cuánto fue suave o intenso", systemImage: "chart.bar") {
            FormAreaScreen(title: "Volumen e intensidad") { VolumeIntensityCard(runs: runs) }
        }
        FormAreaLink(title: "Estadísticas", subtitle: "Distancia, tiempo y ritmo por semana, mes y año", systemImage: "list.number") {
            FormAreaScreen(title: "Estadísticas") { RunningStatsCard(workouts: runs) }
        }
        FormAreaLink(title: "Recuperación del pulso", subtitle: "Cuánto baja el pulso al terminar", systemImage: "heart.circle") {
            FormAreaScreen(title: "Recuperación del pulso") { HeartRateRecoveryCard() }
        }
        FormAreaLink(title: "Récords", subtitle: "Tus 3 mejores de cada récord", systemImage: "trophy") {
            RunRecordsView()
        }
        FormAreaLink(title: "Precisión del modelo", subtitle: "Cuánto acierta la predicción contigo", systemImage: "scope") {
            ModelAccuracyView(runs: runs)
        }
        FormAreaLink(title: "Calidad de los datos", subtitle: flaggedCount > 0 ? String(localized: "\(String(flaggedCount)) para revisar") : String(localized: "Duplicados y datos dudosos"), systemImage: "checkmark.shield") {
            DataQualityView(workouts: rawWorkouts)
        }
    }
}

/// Fila de un área, con el mismo aspecto que la tarjeta «Evolución».
struct FormAreaLink<Destination: View>: View {
    let title: LocalizedStringKey
    let subtitle: String
    let systemImage: String
    @ViewBuilder let destination: () -> Destination

    init(title: LocalizedStringKey, subtitle: String, systemImage: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HalsynCard {
                HStack(spacing: HalsynSpacing.m) {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(.halsynAccentText)
                        .frame(width: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                        Text(LocalizedStringKey(subtitle))
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

/// Pantalla de un área: la tarjeta de siempre, sola.
struct FormAreaScreen<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    init(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HalsynScreen {
            content()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
