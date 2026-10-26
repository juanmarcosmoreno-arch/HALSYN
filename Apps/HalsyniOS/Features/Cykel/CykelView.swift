import HalsynCore
import HalsynDesign
import HealthKit
import SwiftUI

/// CYKEL — bici. Las salidas se registran en el Apple Watch (con medidor de
/// potencia o sensor de cadencia si están emparejados con el reloj); aquí se ven
/// las estadísticas, la potencia y el FTP y el historial. También cuentan las
/// salidas que guarden en Salud otras apps o el app Entreno del reloj.
struct CykelView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var rides: [WorkoutSummary]?
    @State private var showsStartInfo = false

    var body: some View {
        NavigationStack {
            HalsynScreen {
                ModuleHeader(module: .cykel, isDemo: model.isDemo)
                    .padding(.top, HalsynSpacing.s)
                startCard
                if let rides {
                    RunningStatsCard(workouts: rides, sport: .cycling)
                    PowerCard(rides: rides)
                    history(Array(rides.prefix(20)))
                    aboutCard
                } else {
                    HalsynLoadingState()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WorkoutSummary.self) { ride in
                RideDetailView(ride: ride)
            }
            .task(id: model.reloadKey) {
                // Suficientes para las estadísticas del año y los récords.
                rides = await model.provider.recentRides(limit: 400)
            }
            .sheet(isPresented: $showsStartInfo) {
                StartRideInfoSheet()
                    .presentationDetents([.medium])
            }
        }
    }

    private var startCard: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Salida en bici")
                        .font(.halsynTitle)
                        .foregroundStyle(.halsynPrimaryText)
                    Spacer()
                    NavigationLink {
                        RideSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(.halsynAccentText)
                    }
                    .accessibilityLabel(Text("Ajustes de bici"))
                }
                Text("Tiempo, distancia, velocidad, desnivel y frecuencia cardíaca en directo desde tu Apple Watch; potencia y cadencia si emparejas un medidor o un sensor con el reloj.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                HalsynPrimaryButton("Pedalear con Apple Watch", systemImage: "applewatch") {
                    showsStartInfo = true
                }
            }
        }
    }

    @ViewBuilder
    private func history(_ rides: [WorkoutSummary]) -> some View {
        HalsynSectionHeader("Historial", eyebrow: HalsynLexicon.tid.rawValue)
        if rides.isEmpty {
            HalsynEmptyState(systemImage: "bicycle", title: "Sin salidas todavía", message: "Tus salidas en bici guardadas en Apple Health aparecerán aquí.")
        } else {
            VStack(spacing: HalsynSpacing.s) {
                ForEach(rides) { ride in
                    NavigationLink(value: ride) {
                        RideRow(ride: ride, unitSystem: unitSystem)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Por qué la bici, con la evidencia y sus límites.
    private var aboutCard: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Sobre CYKEL", eyebrow: HalsynLexicon.rorelse.rawValue)
                Text("En 263.450 adultos del UK Biobank, quienes iban al trabajo en bici tuvieron un 41 por ciento menos de mortalidad en unos 5 años que quienes no se desplazaban de forma activa (cociente de riesgos 0,59). Es una asociación observada, no prueba que la bici sea la causa.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynPrimaryText)
                Text("Las zonas cardíacas son las de SPRING. En bici la frecuencia cardíaca suele ser algo más baja que corriendo al mismo esfuerzo y los umbrales no se trasladan bien de un deporte a otro: tómalas como orientación.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                ReferenceLinks(references: [ScienceReferences.activeCommuting, ScienceReferences.heartRateTransfer])
            }
        }
    }
}

/// Inicia una salida en el Apple Watch desde el iPhone (`startWatchApp`).
private struct StartRideInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle, starting, started, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            HalsynSymbol().frame(height: 40)
            Text("Pedalear con Apple Watch")
                .font(.halsynTitle)
                .foregroundStyle(.halsynPrimaryText)
            Text("La salida se registra en el reloj, aunque dejes el iPhone en casa. Puedes iniciarla desde aquí o tocando CYKEL en el reloj.")
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
                HalsynPrimaryButton(status == .starting ? "Abriendo el reloj…" : "Iniciar bici al aire libre", systemImage: "applewatch") {
                    Task { await start(indoor: false) }
                }
                .disabled(status == .starting)
                Button {
                    Task { await start(indoor: true) }
                } label: {
                    Label("Iniciar bici en interior", systemImage: "figure.indoor.cycle")
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

    private func start(indoor: Bool) async {
        status = .starting
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = indoor ? .indoor : .outdoor
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

struct RideRow: View {
    let ride: WorkoutSummary
    let unitSystem: UnitSystem

    var body: some View {
        HStack(spacing: HalsynSpacing.m) {
            Image(systemName: ride.activity.systemImage)
                .font(.title3)
                .foregroundStyle(.halsynAccent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.halsynAccentSoft.opacity(0.35)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(ride.activity.title))
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                Text(ride.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let distance = ride.distanceMeters, distance > 0 {
                    Text(verbatim: "\(HalsynFormat.distance(meters: distance, unit: unitSystem)) \(unitSystem.distanceUnitSymbol)")
                        .font(.halsynHeadline.monospacedDigit())
                        .foregroundStyle(.halsynPrimaryText)
                } else {
                    Text(verbatim: HalsynFormat.duration(ride.duration))
                        .font(.halsynHeadline.monospacedDigit())
                        .foregroundStyle(.halsynPrimaryText)
                }
                Text(verbatim: secondary)
                    .font(.halsynCaption.monospacedDigit())
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .padding(HalsynSpacing.m)
        .background(RoundedRectangle(cornerRadius: HalsynRadius.tile, style: .continuous).fill(Color.halsynSurface))
        .overlay(RoundedRectangle(cornerRadius: HalsynRadius.tile, style: .continuous).strokeBorder(Color.halsynHairline, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    /// Velocidad media; sin distancia (rodillo sin sensor), la potencia media o "—".
    private var secondary: String {
        if let speed = ride.averageSpeed {
            return "\(speed.formatted(in: unitSystem)) \(unitSystem.speedUnitSymbol)"
        }
        if let power = ride.averagePower {
            return "\(HalsynFormat.integer(power)) W"
        }
        return "—"
    }
}

#Preview {
    CykelView()
        .environment(AppModel())
}
