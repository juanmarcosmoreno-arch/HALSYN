import Foundation

/// Intervalo de sueño registrado por una fuente (Apple Watch, iPhone, otra app).
public struct SleepSample: Hashable, Sendable {
    public enum Stage: String, Codable, Sendable {
        case inBed
        case awake
        case asleepUnspecified
        case asleepCore
        case asleepDeep
        case asleepREM

        /// `true` para las fases en las que la persona está dormida.
        /// "En cama" y "despierto" no cuentan como sueño.
        public var isAsleep: Bool {
            switch self {
            case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
            case .inBed, .awake: false
            }
        }
    }

    public let start: Date
    public let end: Date
    public let stage: Stage
    public let sourceName: String?

    public init(start: Date, end: Date, stage: Stage, sourceName: String? = nil) {
        self.start = start
        self.end = max(start, end)
        self.stage = stage
        self.sourceName = sourceName
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Agregación de sueño por noche.
///
/// Reglas (documentadas en HEALTHKIT_INTEGRATION.md):
/// - El sueño "del día D" es la noche que termina la mañana de D: ventana
///   [D-1 12:00, D 12:00). Las siestas de la tarde cuentan para el día siguiente.
/// - Solo se suman fases dormidas; "en cama" y "despierto" no cuentan.
/// - Los intervalos solapados (varias fuentes registrando la misma noche) se
///   fusionan antes de sumar, para no contar dos veces el mismo tiempo.
public enum SleepAggregator {
    public static func nightWindow(endingOn day: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let noon = calendar.date(byAdding: .hour, value: 12, to: start) ?? start
        let previousNoon = calendar.date(byAdding: .day, value: -1, to: noon) ?? noon
        return DateInterval(start: previousNoon, end: noon)
    }

    /// Tiempo dormido dentro de la ventana, sin dobles conteos.
    public static func asleepDuration(_ samples: [SleepSample], in window: DateInterval) -> TimeInterval {
        mergedAsleepIntervals(samples, in: window).reduce(0) { $0 + $1.duration }
    }

    /// Fuente con más tiempo dormido registrado en la ventana (para mostrar el origen).
    public static func dominantSource(_ samples: [SleepSample], in window: DateInterval) -> String? {
        var totals: [String: TimeInterval] = [:]
        for sample in samples where sample.stage.isAsleep {
            guard let name = sample.sourceName, let clipped = clip(sample, to: window) else { continue }
            totals[name, default: 0] += clipped.duration
        }
        return totals.max { $0.value < $1.value }?.key
    }

    static func mergedAsleepIntervals(_ samples: [SleepSample], in window: DateInterval) -> [DateInterval] {
        let clipped = samples
            .filter(\.stage.isAsleep)
            .compactMap { clip($0, to: window) }
            .sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in clipped {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func clip(_ sample: SleepSample, to window: DateInterval) -> DateInterval? {
        let start = max(sample.start, window.start)
        let end = min(sample.end, window.end)
        return end > start ? DateInterval(start: start, end: end) : nil
    }
}
