import Foundation

/// Ajustes de SPRING que se editan en el iPhone y se usan en el reloj.
/// Se envían al Apple Watch (WatchConnectivity) como JSON; el reloj guarda la
/// última copia y funciona con ella sin el iPhone.
public struct RunSettings: Hashable, Codable, Sendable {
    public static let autoLapOptions: [Double?] = [nil, 400, 1000, 1609.344, 5000]
    public static let maximumScreens = 4

    /// `nil` = sin vueltas automáticas.
    public var autoLapDistance: Double?
    public var zones: HeartRateZoneConfiguration
    public var alerts: RunAlertConfiguration
    /// Pantallas que se muestran durante la carrera, en orden (1…4).
    public var screens: [WorkoutScreenProfile]
    public var intervalPlans: [IntervalPlan]
    /// Unidades del iPhone, para que el reloj muestre lo mismo.
    public var unitSystem: UnitSystem
    /// Fecha de la última edición: el reloj ignora copias más antiguas.
    public var modifiedAt: Date
    /// Avisos de voz en el reloj. Opcional para leer ajustes guardados antes de existir.
    public var voiceFeedback: Bool?

    /// Dónde suena la voz. Opcional para ajustes guardados antes.
    public var voiceOutput: VoiceOutput?
    /// Qué avisos de voz se dicen (`cues`). Opcional para ajustes guardados antes.
    public var voiceCues: VoiceCueSettings?
    /// Ofrecer medir la recuperación del pulso al terminar (por defecto, sí).
    public var recoveryPrompt: Bool?
    /// Minutos de medición de la recuperación (1, 2 o 5; por defecto, 2).
    public var recoveryMinutes: Int?

    /// CYKEL: vuelta automática en bici, en unidades de distancia (km o mi, las
    /// que estén elegidas). `nil` = la predeterminada (5); 0 = sin vueltas automáticas.
    public var rideAutoLapUnits: Int?
    /// CYKEL: FTP en vatios que eligió el usuario (zonas de potencia en el reloj).
    public var functionalThresholdPower: Double?
    /// CYKEL: zonas cardíacas propias de bici. `nil` = las mismas que SPRING.
    /// La FC a igual esfuerzo y los umbrales cambian entre correr y pedalear.
    public var rideZones: HeartRateZoneConfiguration?

    /// Avisos de voz activados (por defecto, sí).
    public var isVoiceEnabled: Bool {
        get { voiceFeedback ?? true }
        set { voiceFeedback = newValue }
    }

    /// Por defecto en el iPhone: así se oye por los auriculares conectados al
    /// teléfono aunque estés escuchando música en él.
    public var voiceRoute: VoiceOutput {
        get { voiceOutput ?? .phone }
        set { voiceOutput = newValue }
    }

    public init(
        autoLapDistance: Double? = 1000,
        zones: HeartRateZoneConfiguration = .init(),
        alerts: RunAlertConfiguration = .init(),
        screens: [WorkoutScreenProfile] = [.easyRun, .race],
        intervalPlans: [IntervalPlan] = IntervalPlan.presets,
        unitSystem: UnitSystem = .metric,
        modifiedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.autoLapDistance = autoLapDistance
        self.zones = zones
        self.alerts = alerts
        self.screens = screens
        self.intervalPlans = intervalPlans
        self.unitSystem = unitSystem
        self.modifiedAt = modifiedAt
    }

    public static let recoveryMinuteOptions = [1, 2, 5]

    /// Al terminar se ofrece medir cómo baja el pulso.
    public var offersRecovery: Bool {
        get { recoveryPrompt ?? true }
        set { recoveryPrompt = newValue }
    }

    /// Duración de la medición de la recuperación, en minutos.
    public var recoveryDuration: Int {
        get { recoveryMinutes.flatMap { Self.recoveryMinuteOptions.contains($0) ? $0 : nil } ?? 2 }
        set { recoveryMinutes = newValue }
    }

    /// Opciones de vuelta automática en bici, en unidades (0 = desactivada).
    public static let rideAutoLapUnitOptions = [0, 1, 5, 10, 20]
    public static let defaultRideAutoLapUnits = 5

    /// Unidades por vuelta en bici (0 = sin vueltas automáticas). Al cambiar de
    /// km a mi se conserva el número: "cada 5 km" pasa a "cada 5 mi".
    public var rideLapUnits: Int {
        get { max(0, rideAutoLapUnits ?? Self.defaultRideAutoLapUnits) }
        set { rideAutoLapUnits = max(0, newValue) }
    }

    /// Vuelta automática en bici en metros (`nil` = sin vueltas automáticas).
    public var rideAutoLapDistance: Double? {
        rideLapUnits > 0 ? Double(rideLapUnits) * unitSystem.metersPerDistanceUnit : nil
    }

    /// FTP válido (entre 50 y 600 W) o `nil`.
    public var validFunctionalThresholdPower: Double? {
        functionalThresholdPower.flatMap { (50...600).contains($0) ? $0 : nil }
    }

    /// Zonas cardíacas que se usan en bici: las propias o, si no hay, las de SPRING.
    public var cyclingZones: HeartRateZoneConfiguration {
        get { rideZones ?? zones }
        set { rideZones = newValue }
    }

    /// `true` si la bici tiene zonas propias. Al activarlo se parte de una copia
    /// de las de SPRING (sin la FC máxima registrada corriendo, que no es de bici);
    /// al desactivarlo se vuelve a usar las de SPRING.
    public var usesOwnRideZones: Bool {
        get { rideZones != nil }
        set {
            guard newValue else {
                rideZones = nil
                return
            }
            guard rideZones == nil else { return }
            var copy = zones
            if copy.maxSource == .observed { copy.maxHeartRate = nil }
            rideZones = copy
        }
    }

    /// Ajustes para una salida en bici: misma voz, zonas cardíacas de bici,
    /// vuelta automática de bici y sin alertas de ritmo ni de zona (son de carrera).
    public func forRide() -> RunSettings {
        var copy = self
        copy.autoLapDistance = rideAutoLapDistance
        copy.zones = cyclingZones
        copy.alerts = RunAlertConfiguration()
        return copy
    }

    /// Zonas cardíacas del deporte: bici con las suyas; el resto, las de SPRING.
    public func zones(for sport: WorkoutSport) -> HeartRateZoneConfiguration {
        sport == .cycling ? cyclingZones : zones
    }

    /// Pantallas válidas (al menos una). Corrige perfiles incoherentes en vez de fallar.
    public var validScreens: [WorkoutScreenProfile] {
        let valid = screens.prefix(Self.maximumScreens).map { $0.normalized() }
        return valid.isEmpty ? [.easyRun] : Array(valid)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> RunSettings {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(RunSettings.self, from: data)
    }

    /// Lee los ajustes guardados; si no hay o están dañados, devuelve los predeterminados.
    public static func load(from defaults: UserDefaults, key: String = storageKey) -> RunSettings {
        guard let data = defaults.data(forKey: key), let settings = try? decoded(from: data) else { return RunSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults, key: String = RunSettings.storageKey) {
        if let data = try? encoded() {
            defaults.set(data, forKey: key)
        }
    }

    public static let storageKey = "halsyn.spring.settings"
    /// Clave del diccionario de `WCSession.applicationContext`.
    public static let contextKey = "runSettings"
}

extension WorkoutScreenProfile {
    /// Ajusta los campos al número de la distribución: recorta, quita repetidos
    /// y completa con campos que aún no están en pantalla.
    public func normalized() -> WorkoutScreenProfile {
        var unique: [WorkoutFieldKind] = []
        for field in fields where !unique.contains(field) {
            unique.append(field)
        }
        let fillers = WorkoutFieldKind.allCases.filter { !unique.contains($0) }
        unique += fillers.prefix(max(0, layout.fieldCount - unique.count))
        var copy = self
        copy.fields = Array(unique.prefix(layout.fieldCount))
        return copy
    }

    /// Cambia la distribución conservando los campos que quepan.
    public func withLayout(_ layout: WorkoutScreenLayout) -> WorkoutScreenProfile {
        var copy = self
        copy.layout = layout
        return copy.normalized()
    }

    /// Sustituye el campo de la posición `index`; si el nuevo ya estaba en
    /// otra posición, se intercambian (nunca hay repetidos).
    public func replacing(fieldAt index: Int, with field: WorkoutFieldKind) -> WorkoutScreenProfile {
        var copy = normalized()
        guard copy.fields.indices.contains(index) else { return copy }
        if let existing = copy.fields.firstIndex(of: field) {
            copy.fields.swapAt(existing, index)
        } else {
            copy.fields[index] = field
        }
        return copy
    }
}
