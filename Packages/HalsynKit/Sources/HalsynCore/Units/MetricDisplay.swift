import Foundation

/// Representación lista para mostrar de una `MetricAvailability`.
/// Garantiza que la ausencia de datos nunca se muestre como un valor.
public struct MetricDisplay: Hashable, Sendable {
    public let kind: MetricKind
    /// `nil` cuando no hay valor (la UI muestra "—").
    public let value: String?
    public let unit: String
    /// Explicación del estado o del origen del dato.
    public let status: String?
    public let origin: DataOrigin?
    /// Fecha de la lectura (puede ser anterior a hoy, p. ej. VO₂ máx.).
    public let date: Date?

    public init(_ availability: MetricAvailability, kind: MetricKind, unitSystem: UnitSystem = .metric, locale: Locale = .current) {
        self.kind = kind
        unit = HalsynFormat.unitSymbol(for: kind, unit: unitSystem)
        switch availability {
        case .available(let reading):
            value = HalsynFormat.metricValue(reading.value, kind: kind, unit: unitSystem, locale: locale)
            status = nil
            origin = reading.origin
            date = reading.date
        case .noData, .notAuthorized, .unsupported, .temporarilyUnavailable, .readFailed:
            value = nil
            status = availability.statusMessage
            origin = nil
            date = nil
        }
    }
}

/// Cálculos de composición corporal.
public enum BodyMetrics {
    /// Índice de masa corporal (kg/m²). `nil` con valores imposibles.
    public static func bodyMassIndex(weightKilograms: Double, heightMeters: Double) -> Double? {
        guard weightKilograms > 20, weightKilograms < 400, heightMeters > 0.9, heightMeters < 2.6 else { return nil }
        return weightKilograms / (heightMeters * heightMeters)
    }

    /// Cambio de peso: media de los últimos 7 días frente a la de hace 4–6 semanas.
    /// `nil` si falta alguno de los dos tramos.
    public static func monthlyChange(_ values: [DailyValue], endingOn end: Date, calendar: Calendar) -> Double? {
        let last = calendar.startOfDay(for: end)
        func mean(from: Int, to: Int) -> Double? {
            let selected = values.filter { value in
                guard let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: value.day), to: last).day else { return false }
                return days >= from && days <= to
            }.map(\.value)
            return selected.isEmpty ? nil : selected.reduce(0, +) / Double(selected.count)
        }
        guard let recent = mean(from: 0, to: 6), let earlier = mean(from: 28, to: 42) else { return nil }
        return recent - earlier
    }
}
