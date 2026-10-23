import Foundation

/// Tramo continuo de una fase.
public struct SleepSegment: Hashable, Sendable {
    public let start: Date
    public let end: Date
    public let stage: SleepSample.Stage

    public init(start: Date, end: Date, stage: SleepSample.Stage) {
        self.start = start
        self.end = end
        self.stage = stage
    }
}

/// Resumen de una noche (la que termina la mañana de `day`).
///
/// - `asleep` fusiona todas las fuentes sin dobles conteos (igual que `SleepAggregator`).
/// - El reparto por fases usa solo la fuente dominante, para no mezclar las
///   fases de dos aplicaciones distintas en la misma noche.
public struct SleepNight: Hashable, Identifiable, Sendable {
    public let day: Date
    public let asleep: TimeInterval
    /// Primer momento dormido y último momento dormido de la noche.
    public let sleepStart: Date
    public let sleepEnd: Date
    /// Tiempo despierto registrado entre `sleepStart` y `sleepEnd`.
    public let awake: TimeInterval
    /// Segundos por fase (solo de la fuente dominante). Vacío si la fuente no registra fases.
    public let stages: [SleepSample.Stage: TimeInterval]
    /// Tramos de la fuente dominante en orden (para el hipnograma). Vacío si no hay fases.
    public let segments: [SleepSegment]
    public let sourceName: String?
    public let origin: DataOrigin

    public var id: Date { day }

    public init(day: Date, asleep: TimeInterval, sleepStart: Date, sleepEnd: Date, awake: TimeInterval, stages: [SleepSample.Stage: TimeInterval], segments: [SleepSegment] = [], sourceName: String?, origin: DataOrigin) {
        self.day = day
        self.asleep = asleep
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.awake = awake
        self.stages = stages
        self.segments = segments
        self.sourceName = sourceName
        self.origin = origin
    }

    /// Tiempo entre dormirse y despertarse.
    public var sleepPeriod: TimeInterval { sleepEnd.timeIntervalSince(sleepStart) }

    /// Fracción del periodo de sueño pasada dormido (0–1).
    public var efficiency: Double? {
        sleepPeriod > 0 ? min(1, asleep / sleepPeriod) : nil
    }

    /// `true` si hay reparto en fases (núcleo, profundo, REM).
    public var hasStages: Bool {
        [.asleepCore, .asleepDeep, .asleepREM].contains { (stages[$0] ?? 0) > 0 }
    }
}

public enum SleepAnalysis {
    /// Noche que termina la mañana de `day`, o `nil` si no hay sueño registrado.
    public static func night(_ samples: [SleepSample], endingOn day: Date, calendar: Calendar, origin: DataOrigin) -> SleepNight? {
        let window = SleepAggregator.nightWindow(endingOn: day, calendar: calendar)
        let merged = SleepAggregator.mergedAsleepIntervals(samples, in: window)
        guard let first = merged.first, let last = merged.last else { return nil }
        let asleep = merged.reduce(0) { $0 + $1.duration }
        let source = SleepAggregator.dominantSource(samples, in: window)
        let period = DateInterval(start: first.start, end: last.end)

        // Fases de la fuente dominante, recortadas al periodo y sin solapes por fase.
        let own = samples.filter { source == nil || $0.sourceName == source }
        var stages: [SleepSample.Stage: TimeInterval] = [:]
        for stage in [SleepSample.Stage.asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified, .awake] {
            let duration = mergedDuration(own.filter { $0.stage == stage }, in: period)
            if duration > 0 { stages[stage] = duration }
        }
        let awake = stages[.awake] ?? 0
        let segments = own
            .filter { $0.stage != .inBed }
            .compactMap { sample -> SleepSegment? in
                let start = max(sample.start, period.start)
                let end = min(sample.end, period.end)
                return end > start ? SleepSegment(start: start, end: end, stage: sample.stage) : nil
            }
            .sorted { $0.start < $1.start }
        let hasStages = segments.contains { [.asleepCore, .asleepDeep, .asleepREM].contains($0.stage) }
        return SleepNight(day: calendar.startOfDay(for: day), asleep: asleep, sleepStart: first.start, sleepEnd: last.end, awake: awake, stages: stages, segments: hasStages ? segments : [], sourceName: source, origin: origin)
    }

    /// Noches de los `days` días que terminan en `end` (solo las que tienen sueño).
    public static func nights(_ samples: [SleepSample], endingOn end: Date, days: Int, calendar: Calendar, origin: DataOrigin) -> [SleepNight] {
        let last = calendar.startOfDay(for: end)
        return (0..<max(days, 0)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: last).flatMap { night(samples, endingOn: $0, calendar: calendar, origin: origin) }
        }
    }

    /// Ventana completa que cubre `days` noches terminando en `end`.
    public static func window(endingOn end: Date, days: Int, calendar: Calendar) -> DateInterval {
        let last = calendar.startOfDay(for: end)
        let first = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: last) ?? last
        return DateInterval(
            start: SleepAggregator.nightWindow(endingOn: first, calendar: calendar).start,
            end: SleepAggregator.nightWindow(endingOn: last, calendar: calendar).end
        )
    }

    private static func mergedDuration(_ samples: [SleepSample], in window: DateInterval) -> TimeInterval {
        let clipped = samples.compactMap { sample -> DateInterval? in
            let start = max(sample.start, window.start)
            let end = min(sample.end, window.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: DateInterval?
        for interval in clipped {
            if let open = current, interval.start <= open.end {
                current = DateInterval(start: open.start, end: max(open.end, interval.end))
            } else {
                if let open = current { total += open.duration }
                current = interval
            }
        }
        if let open = current { total += open.duration }
        return total
    }
}

/// Regularidad de horarios: media y variación (desviación típica) de la hora
/// de dormirse y de despertarse. Las horas se miden desde el mediodía anterior
/// para que las 23:30 y la 00:30 estén a una hora, no a 23.
public struct SleepRegularity: Hashable, Sendable {
    public static let minimumNights = 5

    public let nights: Int
    /// Minutos desde el mediodía anterior.
    public let averageSleepStart: Double
    public let averageSleepEnd: Double
    /// Desviación típica en minutos.
    public let sleepStartVariation: Double
    public let sleepEndVariation: Double

    /// `nil` con menos de `minimumNights` noches.
    public init?(_ nights: [SleepNight], calendar: Calendar) {
        guard nights.count >= Self.minimumNights else { return nil }
        func minutesFromNoon(_ date: Date, night: SleepNight) -> Double {
            let noon = SleepAggregator.nightWindow(endingOn: night.day, calendar: calendar).start
            return date.timeIntervalSince(noon) / 60
        }
        let starts = Statistics(nights.map { minutesFromNoon($0.sleepStart, night: $0) })
        let ends = Statistics(nights.map { minutesFromNoon($0.sleepEnd, night: $0) })
        self.nights = nights.count
        averageSleepStart = starts.mean
        averageSleepEnd = ends.mean
        sleepStartVariation = starts.standardDeviation
        sleepEndVariation = ends.standardDeviation
    }

    /// Hora y minuto (0–23, 0–59) de un valor en minutos desde el mediodía.
    public static func clockTime(minutesFromNoon minutes: Double) -> (hour: Int, minute: Int) {
        let total = (Int(minutes.rounded()) + 12 * 60) % (24 * 60)
        let wrapped = total < 0 ? total + 24 * 60 : total
        return (wrapped / 60, wrapped % 60)
    }
}

/// Diferencia acumulada con el objetivo de sueño (solo noches por debajo, con datos).
public enum SleepTarget {
    public static let defaultHours = 8.0
    public static let range: ClosedRange<Double> = 6...10

    public static func shortfall(_ nights: [SleepNight], targetHours: Double) -> TimeInterval {
        nights.reduce(0) { $0 + max(0, targetHours * 3600 - $1.asleep) }
    }
}
