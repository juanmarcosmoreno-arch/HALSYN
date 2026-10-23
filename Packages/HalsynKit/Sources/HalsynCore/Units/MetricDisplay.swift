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
