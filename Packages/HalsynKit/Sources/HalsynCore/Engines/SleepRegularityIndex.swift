import Foundation

/// Índice de regularidad del sueño (Sleep Regularity Index, Phillips et al. 2017).
///
/// Probabilidad de estar en el mismo estado (dormido o despierto) a la misma
/// hora en dos días seguidos, escalada de −100 a 100:
/// `SRI = 200 × (minutos coincidentes / minutos comparados) − 100`.
/// 100 = mismo horario exacto cada día; 0 = sin relación entre un día y el siguiente.
///
/// - Cada noche cubre de mediodía a mediodía (12:00 del día anterior → 12:00
///   del día en que terminó). Solo se comparan pares de noches consecutivas.
/// - Dormido = tramos de sueño de la fuente; si la fuente no tiene tramos, se
///   toma como dormido todo el periodo entre dormirse y despertarse.
/// - Solo se ve el sueño nocturno: las siestas no se registran como en los
///   acelerómetros de los estudios, lo que puede subir algo el índice.
public struct SleepRegularityIndex: Hashable, Sendable {
    public static let minimumPairs = 5
    /// Mediana e intervalo intercuartílico en UK Biobank (Windred et al., 2024).
    public static let studyMedian = 81.0
    public static let studyInterquartileRange = 73.8...86.3

    public let value: Double
    /// Pares de días consecutivos comparados.
    public let pairs: Int

    public init(value: Double, pairs: Int) {
        self.value = value
        self.pairs = pairs
    }

    /// `nil` con menos de `minimumPairs` pares de noches consecutivas.
    public static func compute(_ nights: [SleepNight], calendar: Calendar, epochMinutes: Int = 1) -> SleepRegularityIndex? {
        let byDay = Dictionary(nights.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { first, _ in first })
        let epoch = TimeInterval(epochMinutes * 60)
        var agree = 0
        var total = 0
        var pairs = 0
        for (day, night) in byDay {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day), let next = byDay[nextDay],
                  let windowStart = calendar.date(byAdding: .hour, value: -12, to: day) else { continue }
            let first = asleepIntervals(night)
            let second = asleepIntervals(next)
            pairs += 1
            var time = windowStart
            let windowEnd = windowStart.addingTimeInterval(24 * 3600)
            while time < windowEnd {
                let a = contains(first, time)
                let b = contains(second, time.addingTimeInterval(24 * 3600))
                if a == b { agree += 1 }
                total += 1
                time = time.addingTimeInterval(epoch)
            }
        }
        guard pairs >= minimumPairs, total > 0 else { return nil }
        return SleepRegularityIndex(value: 200 * Double(agree) / Double(total) - 100, pairs: pairs)
    }

    static func asleepIntervals(_ night: SleepNight) -> [DateInterval] {
        let asleep = night.segments.filter(\.stage.isAsleep).map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        if !asleep.isEmpty { return asleep }
        return night.sleepEnd > night.sleepStart ? [DateInterval(start: night.sleepStart, end: night.sleepEnd)] : []
    }

    private static func contains(_ intervals: [DateInterval], _ date: Date) -> Bool {
        intervals.contains { $0.start <= date && date < $0.end }
    }
}
