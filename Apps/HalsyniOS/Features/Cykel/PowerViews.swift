import HalsynCore
import HalsynDesign
import Observation
import SwiftUI

/// De dónde sale el FTP que se usa para las zonas, la intensidad y la carga.
enum FTPSource: Equatable {
    /// Lo escribió el usuario (también llega al reloj para las zonas en vivo).
    case manual
    /// Guardado en Apple Health (lo estima el Apple Watch al pedalear con medidor).
    case health(Date)
    /// 95 % de la mejor media de 20 min de las últimas 6 semanas.
    case estimate(FTPEstimate)
}

struct ResolvedFTP: Equatable {
    let watts: Double
    let source: FTPSource
}

/// FTP de Apple Health y estimado desde las salidas, compartidos entre la
/// tarjeta de potencia y el detalle de cada salida.
@MainActor
@Observable
final class FTPStore {
    static let shared = FTPStore()

    private(set) var health: ThresholdPowerReading?
    private(set) var estimate: FTPEstimate?
    private(set) var reloadKey: String?
    /// Fuente de datos con la que se cargó: al pasar de demo a Apple Health (o al
    /// revés) no se mezcla un FTP de una con las salidas de la otra.
    private var mode: DataMode?

    /// Prioridad: el del usuario, el de Apple Health y, si no hay, la estimación.
    func resolved(manual: Double?) -> ResolvedFTP? {
        if let manual { return ResolvedFTP(watts: manual, source: .manual) }
        if let health, (50...600).contains(health.watts) { return ResolvedFTP(watts: health.watts.rounded(), source: .health(health.date)) }
        if let estimate { return ResolvedFTP(watts: estimate.watts, source: .estimate(estimate)) }
        return nil
    }

    /// Lee el FTP de Salud y calcula la estimación con las salidas con potencia
    /// de las últimas 6 semanas (una vez por recarga de datos).
    func load(provider: any HealthDataProviding, rides: [WorkoutSummary], key: String) async {
        resetIfSourceChanged(provider)
        guard reloadKey != key else { return }
        let health = await provider.functionalThresholdPower()
        let start = Calendar.current.date(byAdding: .day, value: -FTPEstimate.windowDays, to: .now) ?? .now
        var bests: [(ride: WorkoutSummary, best20Minutes: Double?)] = []
        for ride in rides where ride.start >= start && ride.averagePower != nil && ride.duration >= 1200 {
            let summary = PowerAnalysis.summary(await provider.ridePower(for: ride))
            bests.append((ride, summary?.best20Minutes))
        }
        // Si la tarea se canceló (cambio de pestaña), las consultas pudieron
        // volver vacías: no se guarda nada y se repite la próxima vez.
        guard !Task.isCancelled, mode == provider.mode else { return }
        self.health = health
        estimate = FTPEstimator.estimate(rides: bests, today: .now, calendar: .current)
        reloadKey = key
    }

    /// Solo el FTP de Salud (desde el detalle si no se pasó por CYKEL).
    func loadHealthIfNeeded(provider: any HealthDataProviding) async {
        resetIfSourceChanged(provider)
        guard reloadKey == nil, health == nil else { return }
        let reading = await provider.functionalThresholdPower()
        guard !Task.isCancelled, mode == provider.mode else { return }
        health = reading
    }

    private func resetIfSourceChanged(_ provider: any HealthDataProviding) {
        guard mode != provider.mode else { return }
        mode = provider.mode
        health = nil
        estimate = nil
        reloadKey = nil
    }
}

/// Colores de las 7 zonas de potencia: de azul (suave) a violeta (máxima).
enum PowerZoneColors {
    static func color(_ zone: Int) -> Color {
        switch zone {
        case 1...5: HalsynZoneColors.color(zone)
        case 6: Color(red: 0.83, green: 0.30, blue: 0.62)
        default: Color(red: 0.55, green: 0.33, blue: 0.85)
        }
    }
}

/// "Potencia y FTP": FTP con su origen, las 7 zonas en vatios y la explicación.
struct PowerCard: View {
    let rides: [WorkoutSummary]
    @Environment(AppModel.self) private var model
    @State private var store = FTPStore.shared
    @State private var settings = RunSettingsStore.shared
    @State private var editing = false

    private var resolved: ResolvedFTP? { store.resolved(manual: settings.settings.validFunctionalThresholdPower) }
    private var hasPowerData: Bool { rides.contains { $0.averagePower != nil } }

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Potencia y FTP", eyebrow: HalsynLexicon.kraft.rawValue)
                if let resolved {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: HalsynFormat.integer(resolved.watts))
                            .font(.system(size: 44, weight: .light).monospacedDigit())
                            .foregroundStyle(.halsynPrimaryText)
                        Text(verbatim: "W")
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynSecondaryText)
                        Spacer()
                        Button("Editar") { editing = true }
                            .font(.halsynCaption.weight(.semibold))
                    }
                    Text(sourceText(resolved.source))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                    suggestion(resolved)
                    PowerZonesList(ftp: resolved.watts)
                } else {
                    Text(hasPowerData
                         ? LocalizedStringKey("Todavía no hay 20 minutos seguidos con potencia en tus salidas de las últimas 6 semanas para estimar tu FTP. Si lo conoces (de un test o de otra app), escríbelo.")
                         : LocalizedStringKey("Para medir potencia necesitas un medidor de potencia Bluetooth emparejado con el Apple Watch (Ajustes › Bluetooth del reloj). Si conoces tu FTP, escríbelo para ver tus zonas."))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynPrimaryText)
                    Button {
                        editing = true
                    } label: {
                        Label("Escribir mi FTP", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.halsynAccent)
                }
                Divider().overlay(Color.halsynHairline)
                Text("El FTP es la potencia más alta que puedes sostener cerca de una hora. Se estima como el 95 por ciento de tu mejor media de 20 minutos. En los estudios coincide de media con el umbral de lactato, pero en cada persona puede desviarse alrededor de un 9 por ciento y suele quedarse corto en ciclistas recreativos: es una referencia para entrenar, no una medida de laboratorio.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                ReferenceLinks(references: [ScienceReferences.powerMeterTraining, ScienceReferences.powerLevels, ScienceReferences.ftpVersusMLSS, ScienceReferences.ftpRecreational])
            }
        }
        .task(id: "\(model.reloadKey)|\(rides.count)") {
            await store.load(provider: model.provider, rides: rides, key: "\(model.reloadKey)|\(rides.count)")
        }
        .sheet(isPresented: $editing) {
            FTPEditorSheet(initial: resolved?.watts)
                .presentationDetents([.medium])
        }
    }

    private func sourceText(_ source: FTPSource) -> LocalizedStringKey {
        switch source {
        case .manual:
            return "Elegido por ti. El reloj lo usa para mostrar tu zona de potencia en directo."
        case let .health(date):
            let day = date.formatted(.dateTime.day().month(.abbreviated).year())
            return "De Apple Health (\(day)). Escríbelo como tuyo para ver tu zona de potencia en el reloj."
        case let .estimate(estimate):
            let best = HalsynFormat.integer(estimate.best20Minutes)
            let day = estimate.rideDate.formatted(.dateTime.day().month(.abbreviated))
            return "Estimado: 95 por ciento de tus mejores 20 minutos (\(best) W, \(day)). Solo vale si esos 20 minutos fueron a tope."
        }
    }

    /// Si hay un FTP de Salud o una estimación distintos del elegido, se ofrece usarlo.
    @ViewBuilder
    private func suggestion(_ resolved: ResolvedFTP) -> some View {
        let candidates: [Double] = [store.health.map { $0.watts.rounded() }, store.estimate?.watts].compactMap { $0 }
        if resolved.source != .manual, let first = candidates.first {
            Button {
                settings.update { $0.functionalThresholdPower = first }
            } label: {
                Label("Usar \(HalsynFormat.integer(first)) W como mi FTP", systemImage: "checkmark.circle")
                    .font(.halsynCaption.weight(.semibold))
            }
        } else if resolved.source == .manual, let health = store.health, abs(health.watts - resolved.watts) >= 5 {
            let value = HalsynFormat.integer(health.watts)
            Button {
                settings.update { $0.functionalThresholdPower = health.watts.rounded() }
            } label: {
                Label("Apple Health tiene \(value) W. Usar ese", systemImage: "arrow.triangle.2.circlepath")
                    .font(.halsynCaption.weight(.semibold))
            }
        }
    }
}

/// Las 7 zonas de Coggan con su rango en vatios.
struct PowerZonesList: View {
    let ftp: Double

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            ForEach(PowerZones.zones) { zone in
                let range = zone.watts(ftp: ftp)
                HStack(spacing: HalsynSpacing.s) {
                    Text(verbatim: "Z\(zone.index)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 30)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(PowerZoneColors.color(zone.index)))
                    Text(LocalizedStringKey(zone.name))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynPrimaryText)
                    Spacer()
                    Text(verbatim: rangeText(range))
                        .font(.halsynCaption.monospacedDigit())
                        .foregroundStyle(.halsynSecondaryText)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Zonas de Coggan en porcentaje del FTP: 55, 75, 90, 105, 120 y 150. El límite del 150 entre Z6 y Z7 es una convención de las apps; Z7 son esfuerzos máximos y cortos.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    private func rangeText(_ range: (lower: Double, upper: Double?)) -> String {
        guard let upper = range.upper else { return "> \(HalsynFormat.integer(range.lower)) W" }
        return "\(HalsynFormat.integer(range.lower))–\(HalsynFormat.integer(upper)) W"
    }
}

/// Escribir o borrar el FTP propio (se guarda en los ajustes y llega al reloj).
struct FTPEditorSheet: View {
    let initial: Double?
    @Environment(\.dismiss) private var dismiss
    @State private var watts: Int = 200

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $watts, in: 50...600, step: 5) {
                        Text(verbatim: "\(watts) W")
                            .font(.title2.monospacedDigit())
                    }
                } footer: {
                    Text("Usa el resultado de un test de 20 minutos (95 por ciento de la media), de un test en laboratorio o el que te dé otra app.")
                }
                if RunSettingsStore.shared.settings.functionalThresholdPower != nil {
                    Section {
                        Button("Borrar mi FTP", role: .destructive) {
                            RunSettingsStore.shared.update { $0.functionalThresholdPower = nil }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Text("Tu FTP"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        RunSettingsStore.shared.update { $0.functionalThresholdPower = Double(watts) }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let initial { watts = Int((initial / 5).rounded() * 5) }
            }
        }
    }
}
