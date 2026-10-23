import Foundation

/// Campos que puede mostrar una pantalla de entrenamiento en el reloj.
///
/// Que un campo exista aquí no garantiza que el dato esté disponible en vivo:
/// la matriz de compatibilidad (`RUNNING_ENGINE.md`) se completará y verificará
/// en dispositivo físico durante las Fases 4 y 5.
public enum WorkoutFieldKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case elapsedTime
    case distance
    case currentPace
    case averagePace
    case heartRate
    case heartRateZone
    case cadence
    case lapTime
    case lapPace
    case targetPace
    case intervalTime
    case runningPower
    case elevationGain

    public var id: String { rawValue }

    /// Etiqueta corta en mayúsculas para la pantalla del reloj.
    public var label: String {
        switch self {
        case .elapsedTime: "TID"
        case .distance: "DISTANCIA"
        case .currentPace: "RITMO"
        case .averagePace: "RITMO MEDIO"
        case .heartRate: "PULS"
        case .heartRateZone: "ZONA"
        case .cadence: "CADENCIA"
        case .lapTime: "TIEMPO VUELTA"
        case .lapPace: "RITMO VUELTA"
        case .targetPace: "RITMO OBJETIVO"
        case .intervalTime: "INTERVALO"
        case .runningPower: "KRAFT"
        case .elevationGain: "DESNIVEL"
        }
    }

    public var title: String {
        switch self {
        case .elapsedTime: "Tiempo"
        case .distance: "Distancia"
        case .currentPace: "Ritmo actual"
        case .averagePace: "Ritmo promedio"
        case .heartRate: "Frecuencia cardíaca"
        case .heartRateZone: "Zona cardíaca"
        case .cadence: "Cadencia"
        case .lapTime: "Tiempo de vuelta"
        case .lapPace: "Ritmo de vuelta"
        case .targetPace: "Ritmo objetivo"
        case .intervalTime: "Tiempo de intervalo"
        case .runningPower: "Potencia de carrera"
        case .elevationGain: "Desnivel acumulado"
        }
    }
}

/// Distribución de campos en pantalla.
public enum WorkoutScreenLayout: Int, CaseIterable, Codable, Sendable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case six = 6

    public var fieldCount: Int { rawValue }
}

/// Perfil de pantallas de entrenamiento (p. ej. Easy Run, Intervals, Race).
public struct WorkoutScreenProfile: Hashable, Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var layout: WorkoutScreenLayout
    public var fields: [WorkoutFieldKind]

    public init(id: String, name: String, layout: WorkoutScreenLayout, fields: [WorkoutFieldKind]) {
        self.id = id
        self.name = name
        self.layout = layout
        self.fields = fields
    }

    /// `true` si el número de campos coincide con la distribución y no hay repetidos.
    public var isValid: Bool {
        fields.count == layout.fieldCount && Set(fields).count == fields.count
    }

    public static let easyRun = WorkoutScreenProfile(
        id: "easy-run", name: "Easy Run", layout: .four,
        fields: [.elapsedTime, .currentPace, .heartRate, .heartRateZone]
    )

    public static let intervals = WorkoutScreenProfile(
        id: "intervals", name: "Intervals", layout: .four,
        fields: [.intervalTime, .currentPace, .targetPace, .heartRate]
    )

    public static let race = WorkoutScreenProfile(
        id: "race", name: "Race", layout: .four,
        fields: [.distance, .averagePace, .elapsedTime, .lapPace]
    )

    public static let defaults: [WorkoutScreenProfile] = [.easyRun, .intervals, .race]
}
