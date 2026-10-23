import HalsynCore
import HalsynDesign
import SwiftUI

/// SPRING — running. Fase 1: historial (demo), resumen semanal y vista previa
/// de las pantallas del reloj. El motor de entrenamiento llega en la Fase 4 y
/// el editor de pantallas en la Fase 5.
struct SpringView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var workouts: [WorkoutSummary]?
    @State private var showsStartInfo = false

    var body: some View {
        NavigationStack {
            HalsynScreen {
                ModuleHeader(module: .spring, isDemo: model.isDemo)
                    .padding(.top, HalsynSpacing.s)
                startCard
                if let workouts {
                    weeklySummary(workouts)
                    watchScreensCard
                    history(workouts)
                } else {
                    HalsynLoadingState()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WorkoutSummary.self) { workout in
                WorkoutDetailView(workout: workout)
            }
            .task {
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HalsynSpacing.xs) {
                        ForEach(RunType.allCases) { type in
                            Label(type.title, systemImage: type.systemImage)
                                .font(.halsynCaption)
                                .padding(.horizontal, HalsynSpacing.s)
                                .padding(.vertical, HalsynSpacing.xs)
                                .foregroundStyle(.halsynAccentText)
                                .background(Capsule().fill(Color.halsynAccentSoft.opacity(0.35)))
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Tipos de carrera previstos"))
            }
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

    private var watchScreensCard: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack {
                    HalsynSectionHeader("Pantallas del reloj", eyebrow: "EASY RUN")
                    PhaseTag(phase: 5)
                }
                HStack(alignment: .center, spacing: HalsynSpacing.l) {
                    WatchScreenPreview(profile: .easyRun)
                        .frame(width: 150)
                    VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
                        Text("Perfil Easy Run")
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                        Text("Tiempo, ritmo, frecuencia cardíaca y zona. El editor para elegir campos, orden y distribución llega en la Fase 5.")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
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

/// Tipos de carrera de la primera versión del motor (Fase 4).
enum RunType: String, CaseIterable, Identifiable {
    case free, time, distance, pace, heartRateZone

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .free: "Libre"
        case .time: "Por tiempo"
        case .distance: "Por distancia"
        case .pace: "Ritmo objetivo"
        case .heartRateZone: "Zona cardíaca"
        }
    }

    var systemImage: String {
        switch self {
        case .free: "figure.run"
        case .time: "timer"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .pace: "speedometer"
        case .heartRateZone: "heart"
        }
    }
}

private struct StartRunInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            HStack {
                HalsynSymbol().frame(height: 40)
                Spacer()
                PhaseTag(phase: 4)
            }
            Text("Las carreras se inician en el Apple Watch")
                .font(.halsynTitle)
                .foregroundStyle(.halsynPrimaryText)
            Text("El motor de entrenamiento (sesión de HealthKit, GPS, ritmo, pausa y guardado) se implementa en la Fase 4 y debe validarse en un Apple Watch físico. En esta fase no se registra ningún entrenamiento.")
                .font(.halsynBody)
                .foregroundStyle(.halsynSecondaryText)
            Spacer()
            HalsynPrimaryButton("Entendido") { dismiss() }
        }
        .padding(HalsynSpacing.l)
        .halsynScreenBackground()
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
