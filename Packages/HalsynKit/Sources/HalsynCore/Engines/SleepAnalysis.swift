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
    /// Sueño fuera del episodio principal (siestas), incluido en `asleep`.
    public var napAsleep: TimeInterval = 0
    /// Tramos de sueño separados por 90 min o más despierto.
    public var episodes: Int = 1
    /// Fuentes que registraron sueño esa noche (se fusionan sin dobles conteos).
    public var sourceCount: Int = 1

    public var id: Date { day }

    /// Sueño del episodio principal (sin siestas).
    public var mainAsleep: TimeInterval { asleep - napAsleep }

    /// Avisos de calidad del registro (no son un diagnóstico).
    public var flags: [SleepNightFlag] {
        var result: [SleepNightFlag] = []
        if napAsleep >= 10 * 60 { result.append(.napIncluded) }
        if sourceCount > 1 { result.append(.multipleSources) }
        // Registro corto: menos de 3 h, o un «sueño de la noche» que termina antes
        // de la medianoche (p. ej. 19:00–22:12): falta el resto de la noche.
        if mainAsleep < 3 * 3600 || sleepEnd <= day { result.append(.shortRecord) }
        if sleepPeriod > 0, awake / sleepPeriod > 0.2 || episodes >= 3 { result.append(.fragmented) }
        return result
    }

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

    /// Fracción del periodo de sueño principal pasada dormido (0–1).
    public var efficiency: Double? {
        sleepPeriod > 0 ? min(1, mainAsleep / sleepPeriod) : nil
    }

    /// `true` si hay reparto en fases (núcleo, profundo, REM).
    public var hasStages: Bool {
        [.asleepCore, .asleepDeep, .asleepREM].contains { (stages[$0] ?? 0) > 0 }
    }
}

/// Algo a revisar en el registro de una noche.
public enum SleepNightFlag: String, Hashable, Sendable {
    /// Hubo siesta (o sueño suelto) además del sueño principal: se suma al
    /// total, pero no mueve el horario de la noche.
    case napIncluded
    /// Varias fuentes registraron la noche (se fusionaron sin contar dos veces).
    case multipleSources
    /// Sueño principal de menos de 3 h, o que termina antes de la medianoche:
    /// puede que el reloj no lo registrara entero.
    case shortRecord
    /// Mucho tiempo despierto o varios tramos separados.
    case fragmented
}

public enum SleepAnalysis {
    /// Separación mínima entre dos tramos de sueño para considerarlos episodios distintos.
    public static let episodeGap: TimeInterval = 90 * 60

    /// Noche que termina la mañana de `day`, o `nil` si no hay sueño registrado.
    public static func night(_ samples: [SleepSample], endingOn day: Date, calendar: Calendar, origin: DataOrigin) -> SleepNight? {
        let window = SleepAggregator.nightWindow(endingOn: day, calendar: calendar)
        let merged = SleepAggregator.mergedAsleepIntervals(samples, in: window)
        guard !merged.isEmpty else { return nil }
        let asleep = merged.reduce(0) { $0 + $1.duration }
        let source = SleepAggregator.dominantSource(samples, in: window)
        // Episodios: tramos separados por 90 min o más; el principal es el de más sueño.
        var episodes: [[DateInterval]] = []
        for interval in merged {
            if let last = episodes.last?.last, interval.start.timeIntervalSince(last.end) < episodeGap {
                episodes[episodes.count - 1].append(interval)
            } else {
                episodes.append([interval])
            }
        }
        let main = episodes.max { a, b in
            a.reduce(0) { $0 + $1.duration } < b.reduce(0) { $0 + $1.duration }
        } ?? merged
        guard let first = main.first, let last = main.last else { return nil }
        let mainAsleep = main.reduce(0) { $0 + $1.duration }
        let period = DateInterval(start: first.start, end: last.end)
        let sources = Set(samples.filter(\.stage.isAsleep).filter { $0.end > window.start && $0.start < window.end }.compactMap(\.sourceName))

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
        var night = SleepNight(day: calendar.startOfDay(for: day), asleep: asleep, sleepStart: first.start, sleepEnd: last.end, awake: awake, stages: stages, segments: hasStages ? segments : [], sourceName: source, origin: origin)
        night.napAsleep = asleep - mainAsleep
        night.episodes = episodes.count
        night.sourceCount = max(sources.count, 1)
        return night
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

/// Patrón de sueño de las últimas semanas: duración, regularidad, tendencia,
/// noches cortas repetidas y registros a revisar.
///
/// Prudencia: las fases del Apple Watch son una estimación del sensor, no una
/// polisomnografía; aquí solo se usan la duración y los horarios.
public struct SleepPattern: Hashable, Sendable {
    /// Horas por noche (con siestas) en las últimas 7 y 28 noches con dato.
    public let average7: Double?
    public let average28: Double?
    /// Desviación típica (minutos) del punto medio del sueño principal.
    public let midpointVariation: Double?
    /// Pendiente (Theil–Sen) en horas por semana de las últimas 28 noches.
    public let trendPerWeek: Double?
    /// Noches de menos de 6 h entre las últimas 7 con dato.
    public let shortNightsLast7: Int
    /// 3 o más noches cortas en la última semana.
    public var repeatedShortSleep: Bool { shortNightsLast7 >= Self.repeatedShortNights }
    /// Noches con algo a revisar (siesta sumada, registro corto, fragmentado, varias fuentes).
    public let flaggedNights: [(day: Date, flags: [SleepNightFlag])]
    /// Noches cuyo punto medio se aparta más de 3 h de tu mediana.
    public let unusualTimingDays: [Date]

    public static let shortNightHours = 6.0
    public static let repeatedShortNights = 3
    public static let unusualTimingMinutes = 180.0

    public static func == (lhs: SleepPattern, rhs: SleepPattern) -> Bool {
        lhs.average7 == rhs.average7 && lhs.average28 == rhs.average28 && lhs.midpointVariation == rhs.midpointVariation
            && lhs.trendPerWeek == rhs.trendPerWeek && lhs.shortNightsLast7 == rhs.shortNightsLast7
            && lhs.flaggedNights.map(\.day) == rhs.flaggedNights.map(\.day) && lhs.unusualTimingDays == rhs.unusualTimingDays
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(average7)
        hasher.combine(average28)
        hasher.combine(shortNightsLast7)
        hasher.combine(unusualTimingDays)
    }

    public static func analyze(_ nights: [SleepNight], calendar: Calendar) -> SleepPattern {
        let sorted = nights.sorted { $0.day < $1.day }
        let last28 = Array(sorted.suffix(28))
        let last7 = Array(sorted.suffix(7))
        func average(_ list: [SleepNight]) -> Double? {
            list.isEmpty ? nil : list.map(\.asleep).reduce(0, +) / Double(list.count) / 3600
        }
        func midpoint(_ night: SleepNight) -> Double {
            let noon = SleepAggregator.nightWindow(endingOn: night.day, calendar: calendar).start
            return (night.sleepStart.timeIntervalSince(noon) + night.sleepEnd.timeIntervalSince(noon)) / 2 / 60
        }
        let midpoints = last28.map(midpoint)
        var variation: Double?
        if midpoints.count >= SleepRegularity.minimumNights {
            variation = Statistics(midpoints).standardDeviation
        }
        var trend: Double?
        if last28.count >= 7, let first = last28.first {
            let points = last28.map { night in
                (x: night.day.timeIntervalSince(first.day) / (7 * 86_400), y: night.asleep / 3600)
            }
            trend = RacePerformanceModel.theilSen(points)
        }
        var unusual: [Date] = []
        if midpoints.count >= SleepRegularity.minimumNights, let median = RacePerformanceModel.median(midpoints) {
            unusual = zip(last28, midpoints).filter { abs($0.1 - median) > unusualTimingMinutes }.map(\.0.day)
        }
        return SleepPattern(
            average7: average(last7),
            average28: average(last28),
            midpointVariation: variation,
            trendPerWeek: trend,
            shortNightsLast7: last7.filter { $0.asleep / 3600 < shortNightHours }.count,
            flaggedNights: last28.compactMap { night in night.flags.isEmpty ? nil : (night.day, night.flags) },
            unusualTimingDays: unusual
        )
    }
}
