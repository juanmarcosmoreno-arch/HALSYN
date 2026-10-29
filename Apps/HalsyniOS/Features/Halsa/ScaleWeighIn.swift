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
    /// Llegó una lectura en vivo (sin estabilizar) en esta búsqueda. Hasta
    /// entonces se ignora la última pesada que la balanza sigue anunciando
    /// (sería la anterior, quizá de otra persona).
    @ObservationIgnored private var sawLoad = false
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    @ObservationIgnored private var seenDevices: Set<UUID> = []

    /// Diagnóstico de la búsqueda (para saber por qué no aparece la balanza).
    struct Diagnostics: Equatable {
        /// Equipos Bluetooth distintos oídos.
        var devices = 0
        /// Nombre de la balanza oída (MI_SCALE, MI SCALE2…), aunque no mande peso.
        var scaleName: String?
        /// Últimos datos de servicio 0x181D / 0x181B, en hexadecimal.
        var lastPayload: String?
        /// Se oyó un equipo Xiaomi cifrado (0xFE95).
        var sawEncrypted = false
        /// Se ignoró la pesada anterior que la balanza seguía anunciando.
        var ignoredPrevious = false
    }

    private(set) var diagnostics = Diagnostics()
    /// Tras estabilizarse, segundos que se espera a la impedancia (llega después del peso).
    static let impedanceWait: TimeInterval = 8

    func start() {
        reading = nil
        lastPayload = nil
        stabilizedAt = nil
        sawLoad = false
        seenDevices = []
        diagnostics = Diagnostics()
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
            // Sin filtro de servicios: la balanza manda el peso en «datos de
            // servicio» y no siempre pone 0x181D en su lista de servicios, que es
            // lo único que mira el filtro de iOS. Se filtra en `received`.
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
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

    fileprivate func received(_ advertisement: ScaleAdvertisement) {
        guard state == .scanning || state == .measuring else { return }
        if seenDevices.insert(advertisement.peripheral).inserted {
            diagnostics.devices = seenDevices.count
        }
        if let name = advertisement.name, Self.looksLikeScale(name) {
            diagnostics.scaleName = name
        }
        for (uuid, data) in advertisement.serviceData {
            let short = XiaomiScaleParser.shortUUID(uuid)
            if short == XiaomiScaleParser.encryptedServiceUUID {
                diagnostics.sawEncrypted = true
            }
            guard short == XiaomiScaleParser.weightServiceUUID || short == XiaomiScaleParser.bodyCompositionServiceUUID else { continue }
            diagnostics.lastPayload = "\(short): " + data.map { String(format: "%02X", $0) }.joined(separator: " ")
            guard data != lastPayload,
                  let parsed = XiaomiScaleParser.parse(serviceUUID: short, data: [UInt8](data)) else { continue }
            lastPayload = data
            // Una pesada en vivo siempre manda primero lecturas sin estabilizar.
            // Hasta ver una, lo estable es la pesada anterior que la balanza
            // sigue anunciando (aunque no diga «retirado»): no se muestra.
            if !parsed.isStabilized, !parsed.isLoadRemoved {
                sawLoad = true
            }
            guard sawLoad else {
                diagnostics.ignoredPrevious = true
                continue
            }
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

    private static func looksLikeScale(_ name: String) -> Bool {
        let upper = name.uppercased()
        return upper.contains("MI_SCALE") || upper.contains("MI SCALE") || upper.contains("MIBFS") || upper.contains("XMTZC")
    }

    private func finish() {
        guard state != .finished, reading?.isStabilized == true else { return }
        waitTask?.cancel()
        central?.stopScan()
        state = .finished
    }
}

/// Lo que interesa de un anuncio BLE, copiado para pasarlo al hilo principal.
struct ScaleAdvertisement: Sendable {
    let peripheral: UUID
    let name: String?
    let serviceData: [String: Data]
}

extension ScaleScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in self.stateChanged(central) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]) ?? [:]
        let advertisement = ScaleAdvertisement(
            peripheral: peripheral.identifier,
            name: (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name,
            serviceData: Dictionary(uniqueKeysWithValues: serviceData.map { ($0.key.uuidString, $0.value) })
        )
        Task { @MainActor in self.received(advertisement) }
    }
}

/// Guarda el peso (y, si se elige, la grasa estimada) en Apple Health.
@MainActor
enum ScaleHealthWriter {
    enum WriteError: LocalizedError {
        case weightNotAllowed

        var errorDescription: String? {
            String(localized: "HÅLSYN no tiene permiso para guardar el peso. Actívalo en Salud › Compartir › Apps › HÅLSYN › Peso.")
        }
    }

    /// Guarda el peso; la grasa solo si hay permiso para ella. Devuelve si la grasa se guardó.
    @discardableResult
    static func save(weightKilograms: Double, bodyFatPercent: Double?, model: XiaomiScaleReading.Model) async throws -> Bool {
        let store = HKHealthStore()
        let types: Set<HKSampleType> = bodyFatPercent == nil
            ? [HKQuantityType(.bodyMass)]
            : [HKQuantityType(.bodyMass), HKQuantityType(.bodyFatPercentage)]
        if types.contains(where: { store.authorizationStatus(for: $0) == .notDetermined }) {
            try await store.requestAuthorization(toShare: types, read: [])
        }
        guard store.authorizationStatus(for: HKQuantityType(.bodyMass)) == .sharingAuthorized else {
            throw WriteError.weightNotAllowed
        }
        let now = Date()
        let device = HKDevice(
            name: model == .bodyComposition ? "Mi Body Composition Scale 2" : "Mi Smart Scale 2",
            manufacturer: "Xiaomi",
            model: nil, hardwareVersion: nil, firmwareVersion: nil, softwareVersion: nil,
            localIdentifier: nil, udiDeviceIdentifier: nil
        )
        // Por separado: si la grasa no tiene permiso, el peso se guarda igual.
        try await store.save(HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKilograms), start: now, end: now, device: device, metadata: nil))
        guard let bodyFatPercent, store.authorizationStatus(for: HKQuantityType(.bodyFatPercentage)) == .sharingAuthorized else {
            return false
        }
        try await store.save(HKQuantitySample(type: HKQuantityType(.bodyFatPercentage), quantity: HKQuantity(unit: .percent(), doubleValue: bodyFatPercent / 100), start: now, end: now, device: nil, metadata: nil))
        return true
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
    /// Se pidió guardar la grasa y no había permiso para ella.
    @State private var fatSkipped = false
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
                    diagnostics
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
            HalsynStatusIndicator(.positive, text: fatSkipped ? String(localized: "Peso guardado en Apple Health. La grasa no: falta el permiso en Salud.") : String(localized: "Guardado en Apple Health."))
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
                errorMessage = nil
                scanner.start()
            }
            .font(.halsynCaption)
        }
    }

    /// Qué oye el iPhone: sirve para saber si la balanza no se oye, se oye sin
    /// peso o manda datos que no se entienden.
    private var diagnostics: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let info = scanner.diagnostics
            let waited = scanner.searchStarted.map { context.date.timeIntervalSince($0) } ?? 0
            VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
                Text("Equipos Bluetooth oídos: \(info.devices)")
                if let name = info.scaleName {
                    Text("Balanza oída: \(name)")
                }
                if info.ignoredPrevious, scanner.reading == nil {
                    Text("La balanza todavía anuncia la pesada anterior (no se usa). Súbete para pesarte de nuevo; si ya estabas arriba, bájate y vuelve a subir.")
                }
                if let payload = info.lastPayload {
                    Text("Últimos datos: \(payload)")
                        .monospaced()
                        .textSelection(.enabled)
                } else if waited > 20, scanner.state == .scanning {
                    if info.scaleName != nil {
                        Text("Se oye la balanza pero todavía no manda el peso. Súbete y espera a que el número quede fijo en la pantalla de la balanza.")
                    } else if info.sawEncrypted {
                        Text("Se oyen equipos Xiaomi cifrados, pero ninguna balanza que mande el peso sin cifrar.")
                    } else {
                        Text("No se oye ninguna balanza. Pisa la balanza para encenderla, acerca el iPhone y cierra Zepp Life (si está conectada a ella, puede dejar de anunciarse).")
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.halsynSecondaryText)
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
            let fatSaved = try await ScaleHealthWriter.save(weightKilograms: (reading.weightKilograms * 100).rounded() / 100, bodyFatPercent: fat.map { $0.percent.rounded() }, model: reading.model)
            fatSkipped = fat != nil && !fatSaved
            saved = true
            model.refresh()
        } catch let error as ScaleHealthWriter.WriteError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = String(localized: "No se pudo guardar en Salud: \(error.localizedDescription)")
        }
        saving = false
    }
}
