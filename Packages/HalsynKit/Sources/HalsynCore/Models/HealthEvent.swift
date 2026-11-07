import Foundation

/// Un evento de salud que registras tú: una enfermedad, un medicamento, una
/// lesión, una vacuna… HÅLSYN lo usa solo para dar **contexto** (marcarlo en
/// las gráficas, no contar como incumplimiento las sesiones de esos días y
/// bajar la intensidad del plan). Nunca diagnostica ni atribuye causas.
public struct HealthEvent: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case illness, symptom, fever, medication, injury, vaccination, stress, recoveryDay

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .illness: "Enfermedad"
            case .symptom: "Síntoma"
            case .fever: "Fiebre"
            case .medication: "Medicación o tratamiento"
            case .injury: "Lesión"
            case .vaccination: "Vacuna"
            case .stress: "Estrés extraordinario"
            case .recoveryDay: "Día de recuperación"
            }
        }

        public var systemImage: String {
            switch self {
            case .illness: "allergens"
            case .symptom: "stethoscope"
            case .fever: "thermometer.medium"
            case .medication: "pills"
            case .injury: "bandage"
            case .vaccination: "syringe"
            case .stress: "brain.head.profile"
            case .recoveryDay: "bed.double"
            }
        }

        /// Impide entrenar con normalidad: sus días no cuentan como incumplimiento.
        public var affectsTraining: Bool { self == .illness || self == .fever || self == .injury }
    }

    public var id: UUID
    public var kind: Kind
    /// Nombre libre, p. ej. «Sinusitis» o «Ibuprofeno».
    public var title: String
    public var start: Date
    /// `nil` = sigue (en curso).
    public var end: Date?
    public var note: String?

    public init(id: UUID = UUID(), kind: Kind, title: String, start: Date, end: Date? = nil, note: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end.map { max($0, start) }
        self.note = note
    }

    public var isOngoing: Bool { end == nil }

    /// Último día (inclusive); en curso = `today`.
    public func lastDay(today: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: end ?? today)
    }

    /// El evento abarca ese día (inicio y fin inclusive).
    public func covers(_ day: Date, today: Date, calendar: Calendar) -> Bool {
        let target = calendar.startOfDay(for: day)
        return target >= calendar.startOfDay(for: start) && target <= lastDay(today: today, calendar: calendar)
    }

    /// Días que abarca, hasta `today` como mucho.
    public func days(today: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = min(lastDay(today: today, calendar: calendar), calendar.startOfDay(for: today))
        while day <= last, result.count < 3660 {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}

extension Array where Element == HealthEvent {
    /// Días en los que un evento impedía entrenar (para la adherencia).
    public func trainingAffectedDays(today: Date, calendar: Calendar) -> Set<Date> {
        Set(filter(\.kind.affectsTraining).flatMap { $0.days(today: today, calendar: calendar) })
    }

    /// Eventos que se cruzan con un intervalo de días (para las gráficas).
    public func overlapping(from start: Date, to end: Date, today: Date, calendar: Calendar) -> [HealthEvent] {
        filter { event in
            calendar.startOfDay(for: event.start) <= calendar.startOfDay(for: end)
                && event.lastDay(today: today, calendar: calendar) >= calendar.startOfDay(for: start)
        }
        .sorted { $0.start < $1.start }
    }
}
