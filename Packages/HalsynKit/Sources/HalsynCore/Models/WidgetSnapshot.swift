import Foundation

/// Resumen que la app deja para sus widgets y complicaciones.
///
/// Los widgets no leen Apple Health: muestran lo último que calculó la app
/// (al abrirla o al refrescar en segundo plano) y la hora de esa lectura.
/// Se guarda en el contenedor del grupo de apps, solo en el dispositivo.
public struct WidgetSnapshot: Hashable, Codable, Sendable {
    public struct GoalSummary: Hashable, Codable, Sendable {
        public var title: String
        public var fraction: Double
        public var isCompleted: Bool

        public init(title: String, fraction: Double, isCompleted: Bool) {
            self.title = title
            self.fraction = min(max(fraction, 0), 1)
            self.isCompleted = isCompleted
        }
    }

    /// Sesión del plan para un día (textos ya localizados por la app).
    public struct SessionSummary: Hashable, Codable, Sendable {
        public var date: Date
        public var title: String
        public var detail: String?
        public var symbol: String
        public var isRest: Bool

        public init(date: Date, title: String, detail: String?, symbol: String, isRest: Bool) {
            self.date = date
            self.title = title
            self.detail = detail
            self.symbol = symbol
            self.isRest = isRest
        }
    }

    public var updatedAt: Date
    public var score: Int?
    /// Texto ya localizado de la banda ("Buena condición").
    public var scoreBand: String?
    public var recovery: Int?
    public var steps: Double?
    public var sleepHours: Double?
    public var goal: GoalSummary?
    public var isDemo: Bool
    /// Entrenamiento del plan para hoy (`nil` sin plan o sin sesión).
    public var session: SessionSummary?

    /// La sesión, solo si es la de `date` (el widget no muestra la de ayer).
    public func session(on date: Date, calendar: Calendar) -> SessionSummary? {
        session.flatMap { calendar.isDate($0.date, inSameDayAs: date) ? $0 : nil }
    }

    public init(updatedAt: Date, score: Int? = nil, scoreBand: String? = nil, recovery: Int? = nil, steps: Double? = nil, sleepHours: Double? = nil, goal: GoalSummary? = nil, isDemo: Bool) {
        self.updatedAt = updatedAt
        self.score = score.map { min(max($0, 0), 100) }
        self.scoreBand = scoreBand
        self.recovery = recovery.map { min(max($0, 0), 100) }
        self.steps = steps
        self.sleepHours = sleepHours
        self.goal = goal
        self.isDemo = isDemo
    }

    /// Ejemplo para la galería de widgets (siempre marcado como demo).
    public static let placeholder = WidgetSnapshot(
        updatedAt: Date(timeIntervalSince1970: 0), score: 82, scoreBand: nil, recovery: 74, steps: 8420, sleepHours: 7.4,
        goal: GoalSummary(title: "8.000", fraction: 0.8, isCompleted: false), isDemo: true
    )

    /// `true` si los datos tienen más de `hours` horas (el widget lo indica).
    public func isStale(at date: Date, hours: Double = 6) -> Bool {
        date.timeIntervalSince(updatedAt) > hours * 3600
    }

    /// Los valores del día solo valen el mismo día: después se ocultan.
    public func isFromToday(_ date: Date, calendar: Calendar) -> Bool {
        calendar.isDate(updatedAt, inSameDayAs: date)
    }
}

/// Lectura y escritura del resumen en un `UserDefaults` compartido.
public enum WidgetSnapshotStore {
    public static let key = "halsyn.widget.snapshot"

    /// Grupo de apps: "group." + bundle ID de la app de iPhone (el reloj usa el mismo prefijo).
    public static func groupIdentifier(bundleIdentifier: String?) -> String? {
        guard var base = bundleIdentifier else { return nil }
        for suffix in [".watchkitapp.widgets", ".watchkitapp", ".widgets"] where base.hasSuffix(suffix) {
            base.removeLast(suffix.count)
            break
        }
        return "group.\(base)"
    }

    public static func encode(_ snapshot: WidgetSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: WidgetSnapshot, to defaults: UserDefaults, key: String = Self.key) {
        if let data = encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    public static func load(from defaults: UserDefaults, key: String = Self.key) -> WidgetSnapshot? {
        defaults.data(forKey: key).flatMap(decode)
    }

    /// `UserDefaults` del grupo para el bundle actual, o `nil` si no está configurado.
    public static func sharedDefaults(bundle: Bundle = .main) -> UserDefaults? {
        groupIdentifier(bundleIdentifier: bundle.bundleIdentifier).flatMap(UserDefaults.init(suiteName:))
    }
}
