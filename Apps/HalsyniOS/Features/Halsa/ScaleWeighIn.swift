import CoreBluetooth
import HalsynCore
import HalsynDesign
import HealthKit
import Observation
import SwiftUI

/// Lee la balanza Xiaomi directamente por Bluetooth, sin Zepp Life: escucha la
/// publicidad BLE de la Mi Smart Scale 2 (0x181D) y de la Mi Body Composition
/// Scale 2 (0x181B) mientras la pantalla está abierta. No empareja ni se conecta.
@MainActor
@Observable
final class ScaleScanner: NSObject {
    enum State: Equatable {
        case idle
        case unauthorized
        case poweredOff
        case unsupported
        case scanning
        /// La balanza está midiendo (el peso todavía cambia).
        case measuring
        /// Lectura final (estable; con impedancia si la balanza la da).
        case finished
    }

    private(set) var state: State = .idle
    private(set) var reading: XiaomiScaleReading?
    /// Segundos buscando sin encontrar ninguna balanza compatible.
    private(set) var searchStarted: Date?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var lastPayload: Data?
    @ObservationIgnored private var stabilizedAt: Date?
    @ObservationIgnored private var waitTask: Task<Void, Never>?

    static let services = [CBUUID(string: XiaomiScaleParser.bodyCompositionServiceUUID), CBUUID(string: XiaomiScaleParser.weightServiceUUID)]
    /// Tras estabilizarse, segundos que se espera a la impedancia (llega después del peso).
    static let impedanceWait: TimeInterval = 8

    func start() {
        reading = nil
        lastPayload = nil
        stabilizedAt = nil
        searchStarted = .now
        if let central {
            begin(central)
        } else {
            // Crear el gestor muestra el permiso de Bluetooth la primera vez.
            central = CBCentralManager(delegate: self, queue: nil)
        }
    }

    func stop() {
        waitTask?.cancel()
        central?.stopScan()
        if state == .scanning || state == .measuring { state = .idle }
    }

    private func begin(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            state = .scanning
            central.scanForPeripherals(withServices: Self.services, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        case .unauthorized:
            state = .unauthorized
        case .poweredOff:
            state = .poweredOff
        case .unsupported:
            state = .unsupported
        default:
            break
        }
    }

    fileprivate func stateChanged(_ central: CBCentralManager) {
        guard state != .finished else { return }
        begin(central)
    }

    fileprivate func received(_ serviceData: [CBUUID: Data]) {
        guard state == .scanning || state == .measuring else { return }
        for (uuid, data) in serviceData {
            guard data != lastPayload,
                  let parsed = XiaomiScaleParser.parse(serviceUUID: uuid.uuidString, data: [UInt8](data)) else { continue }
            lastPayload = data
            reading = parsed
            if !parsed.isStabilized {
                state = .measuring
                stabilizedAt = nil
                continue
            }
            // Peso estable: si es la de composición y aún no hay impedancia,
            // se espera un poco (llega unos segundos después, con pies descalzos).
            if parsed.model == .weightOnly || parsed.impedance != nil || parsed.isLoadRemoved {
                finish()
            } else if stabilizedAt == nil {
                stabilizedAt = .now
                state = .measuring
                waitTask?.cancel()
                waitTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.impedanceWait))
                    guard !Task.isCancelled else { return }
                    self?.finish()
                }
            }
        }
    }

    private func finish() {
        guard state != .finished, reading?.isStabilized == true else { return }
        waitTask?.cancel()
        central?.stopScan()
        state = .finished
    }
}

extension ScaleScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in self.stateChanged(central) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] else { return }
        Task { @MainActor in self.received(serviceData) }
    }
}

/// Guarda el peso (y, si se elige, la grasa estimada) en Apple Health.
@MainActor
enum ScaleHealthWriter {
    static func save(weightKilograms: Double, bodyFatPercent: Double?, model: XiaomiScaleReading.Model) async throws {
        let store = HKHealthStore()
        let types: Set<HKSampleType> = bodyFatPercent == nil
            ? [HKQuantityType(.bodyMass)]
            : [HKQuantityType(.bodyMass), HKQuantityType(.bodyFatPercentage)]
        if types.contains(where: { store.authorizationStatus(for: $0) == .notDetermined }) {
            try await store.requestAuthorization(toShare: types, read: [])
        }
        let now = Date()
        let device = HKDevice(
            name: model == .bodyComposition ? "Mi Body Composition Scale 2" : "Mi Smart Scale 2",
            manufacturer: "Xiaomi",
            model: nil, hardwareVersion: nil, firmwareVersion: nil, softwareVersion: nil,
            localIdentifier: nil, udiDeviceIdentifier: nil
        )
        var samples: [HKObject] = [
            HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKilograms), start: now, end: now, device: device, metadata: nil),
        ]
        if let bodyFatPercent {
            samples.append(HKQuantitySample(type: HKQuantityType(.bodyFatPercentage), quantity: HKQuantity(unit: .percent(), doubleValue: bodyFatPercent / 100), start: now, end: now, device: device, metadata: nil))
        }
        try await store.save(samples)
    }
}

/// Pesarse con la balanza Xiaomi desde la app.
struct ScaleWeighInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var scanner = ScaleScanner()
    @State private var saveFat = false
    @State private var saving = false
    @State private var saved = false
    @State private var errorMessage: String?
    private var profile: ReferenceProfileStore { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HalsynSpacing.l) {
                    status
                    if let reading = scanner.reading {
                        weight(reading)
                        if scanner.state == .finished {
                            result(reading)
                        }
                    }
                    help
                }
                .padding(HalsynSpacing.l)
            }
            .halsynScreenBackground()
            .navigationTitle("Balanza Xiaomi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear { scanner.start() }
            .onDisappear { scanner.stop() }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch scanner.state {
        case .idle, .scanning:
            Label("Súbete a la balanza descalzo. HÅLSYN la escucha por Bluetooth: no hace falta emparejarla ni abrir Zepp Life.", systemImage: "dot.radiowaves.left.and.right")
                .font(.halsynBody)
        case .measuring:
            Label("Midiendo… quédate quieto hasta que el número se detenga.", systemImage: "scalemass")
                .font(.halsynBody)
        case .finished:
            Label("Listo. Ya puedes bajarte.", systemImage: "checkmark.circle.fill")
                .font(.halsynBody)
                .foregroundStyle(.halsynPositive)
        case .unauthorized:
            Label("HÅLSYN no tiene permiso de Bluetooth. Actívalo en Ajustes › Privacidad y seguridad › Bluetooth › HÅLSYN.", systemImage: "exclamationmark.triangle")
                .font(.halsynBody)
                .foregroundStyle(.halsynCaution)
        case .poweredOff:
            Label("El Bluetooth del iPhone está apagado.", systemImage: "exclamationmark.triangle")
                .font(.halsynBody)
                .foregroundStyle(.halsynCaution)
        case .unsupported:
            Label("Este dispositivo no tiene Bluetooth de bajo consumo.", systemImage: "exclamationmark.triangle")
                .font(.halsynBody)
                .foregroundStyle(.halsynCaution)
        }
    }

    private func weight(_ reading: XiaomiScaleReading) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: HalsynFormat.decimal(reading.weightKilograms / unitSystem.kilogramsPerMassUnit, fractionDigits: 2))
                .font(.system(size: 56, weight: .light).monospacedDigit())
                .foregroundStyle(reading.isStabilized ? Color.halsynPrimaryText : Color.halsynSecondaryText)
                .contentTransition(.numericText())
            Text(verbatim: unitSystem.massUnitSymbol)
                .font(.halsynHeadline)
                .foregroundStyle(.halsynSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func result(_ reading: XiaomiScaleReading) -> some View {
        let estimate = fatEstimate(reading)
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                if let height = profile.heightCentimeters, let bmi = BodyMetrics.bodyMassIndex(weightKilograms: reading.weightKilograms, heightMeters: height / 100) {
                    LabeledContent("IMC", value: HalsynFormat.decimal(bmi, fractionDigits: 1))
                }
                if let estimate {
                    let lower = HalsynFormat.integer(estimate.lower)
                    let upper = HalsynFormat.integer(estimate.upper)
                    LabeledContent("Grasa estimada") {
                        Text(verbatim: "≈ \(HalsynFormat.integer(estimate.percent)) % (\(lower)–\(upper))")
                            .monospacedDigit()
                    }
                    Text("Estimación con la ecuación publicada de Jebb y colaboradores (2000), hecha con otra balanza de pies (Tanita) y no validada en Xiaomi: el error de una persona ronda ±8 puntos. Será distinta de la de Zepp Life, cuyo cálculo no es público. Mira la tendencia de semanas, no un día.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                    Toggle("Guardar también la grasa estimada en Salud", isOn: $saveFat)
                        .font(.halsynCaption)
                    ReferenceLinks(references: [ScienceReferences.footToFootBodyFat])
                } else if reading.model == .weightOnly {
                    Text("Esta balanza mide solo el peso (no tiene electrodos para la grasa).")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                } else {
                    Text(reading.impedance == nil
                         ? LocalizedStringKey("Sin impedancia (hay que subirse descalzo y con los pies secos): solo se guarda el peso.")
                         : LocalizedStringKey("Para estimar la grasa hacen falta tu altura, tu edad y tu sexo en Perfil (y estar dentro de lo estudiado: 16–78 años, IMC 16–41)."))
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        if saved {
            HalsynStatusIndicator(.positive, text: "Guardado en Apple Health.")
            HalsynPrimaryButton("Listo") { dismiss() }
        } else {
            if let errorMessage {
                HalsynStatusIndicator(.caution, text: errorMessage)
            }
            HalsynPrimaryButton(saving ? "Guardando…" : "Guardar en Apple Health", systemImage: "heart.text.square") {
                Task { await save(reading, fat: saveFat ? estimate : nil) }
            }
            .disabled(saving || model.isDemo)
            if model.isDemo {
                Text("En modo demo no se guarda en Salud.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
            Button("Volver a pesar") {
                saved = false
                scanner.start()
            }
            .font(.halsynCaption)
        }
    }

    private var help: some View {
        Text("Funciona con la Mi Smart Scale 2 y la Mi Body Composition Scale 2 (las de Zepp Life). Las nuevas Xiaomi S400 y S200 cifran sus datos y solo se leen con la app de Xiaomi. Si no aparece nada, pisa la balanza para despertarla y deja el iPhone cerca.")
            .font(.caption2)
            .foregroundStyle(.halsynSecondaryText)
    }

    private func fatEstimate(_ reading: XiaomiScaleReading) -> BodyFatEstimate? {
        guard let impedance = reading.impedance,
              let height = profile.heightCentimeters,
              let age = profile.age,
              let sex = profile.sex else { return nil }
        return BodyFatEstimate.jebb2000(weightKilograms: reading.weightKilograms, heightMeters: height / 100, age: Double(age), sex: sex, impedance: impedance)
    }

    private func save(_ reading: XiaomiScaleReading, fat: BodyFatEstimate?) async {
        saving = true
        errorMessage = nil
        do {
            try await ScaleHealthWriter.save(weightKilograms: (reading.weightKilograms * 100).rounded() / 100, bodyFatPercent: fat.map { ($0.percent * 10).rounded() / 10 }, model: reading.model)
            saved = true
            model.refresh()
        } catch {
            errorMessage = String(localized: "No se pudo guardar en Salud: \(error.localizedDescription)")
        }
        saving = false
    }
}
