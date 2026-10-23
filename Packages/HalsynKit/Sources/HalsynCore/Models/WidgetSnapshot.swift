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

    public var updatedAt: Date
    public var score: Int?
    /// Texto ya localizado de la banda ("Buena condición").
    public var scoreBand: String?
    public var recovery: Int?
    public var steps: Double?
    public var sleepHours: Double?
    public var goal: GoalSummary?
    public var isDemo: Bool

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

    public static func save(_ snapshot: WidgetSnapshot, to defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    public static func load(from defaults: UserDefaults) -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// `UserDefaults` del grupo para el bundle actual, o `nil` si no está configurado.
    public static func sharedDefaults(bundle: Bundle = .main) -> UserDefaults? {
        groupIdentifier(bundleIdentifier: bundle.bundleIdentifier).flatMap(UserDefaults.init(suiteName:))
    }
}
