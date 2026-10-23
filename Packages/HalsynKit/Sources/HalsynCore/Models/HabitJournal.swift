import Foundation

/// Hábito o circunstancia que el usuario marca en su diario de un día.
public enum HabitTag: String, Codable, CaseIterable, Identifiable, Sendable {
    case alcohol
    case lateCaffeine
    case lateMeal
    case stress
    case sick
    case travel
    case screensInBed
    case nap
    case meditation
    case sauna

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .alcohol: "Alcohol"
        case .lateCaffeine: "Cafeína por la tarde"
        case .lateMeal: "Cena tarde o pesada"
        case .stress: "Día estresante"
        case .sick: "Enfermo o con síntomas"
        case .travel: "Viaje"
        case .screensInBed: "Pantallas en la cama"
        case .nap: "Siesta"
        case .meditation: "Meditación o respiración"
        case .sauna: "Sauna"
        }
    }

    public var systemImage: String {
        switch self {
        case .alcohol: "wineglass"
        case .lateCaffeine: "cup.and.saucer"
        case .lateMeal: "fork.knife"
        case .stress: "bolt.heart"
        case .sick: "facemask"
        case .travel: "airplane"
        case .screensInBed: "iphone"
        case .nap: "powersleep"
        case .meditation: "wind"
        case .sauna: "flame"
        }
    }
}

/// Diario: qué días se registró y qué se marcó cada día.
///
/// Solo cuentan como "sin la etiqueta" los días que el usuario **registró**
/// (aunque no marcara nada). Un día sin registrar no dice nada.
public struct HabitJournal: Codable, Hashable, Sendable {
    /// Día (inicio del día, como intervalo desde 2001) → etiquetas.
    public private(set) var entries: [Double: Set<HabitTag>] = [:]

    public init() {}

    public func tags(on day: Date, calendar: Calendar) -> Set<HabitTag>? {
        entries[calendar.startOfDay(for: day).timeIntervalSinceReferenceDate]
    }

    public func isLogged(_ day: Date, calendar: Calendar) -> Bool {
        tags(on: day, calendar: calendar) != nil
    }

    public mutating func set(_ tags: Set<HabitTag>, on day: Date, calendar: Calendar) {
        entries[calendar.startOfDay(for: day).timeIntervalSinceReferenceDate] = tags
    }

    public mutating func remove(_ day: Date, calendar: Calendar) {
        entries[calendar.startOfDay(for: day).timeIntervalSinceReferenceDate] = nil
    }

    public var loggedDays: [Date] {
        entries.keys.sorted().map(Date.init(timeIntervalSinceReferenceDate:))
    }

    /// Días seguidos registrados hasta hoy (o ayer, si hoy aún no).
    public func streak(endingOn day: Date, calendar: Calendar) -> Int {
        var cursor = calendar.startOfDay(for: day)
        if !isLogged(cursor, calendar: calendar) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var count = 0
        while isLogged(cursor, calendar: calendar) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

public enum HabitJournalStorage {
    public static let key = "halsyn.journal"

    public static func load(from defaults: UserDefaults) -> HabitJournal {
        guard let data = defaults.data(forKey: key),
              let journal = try? JSONDecoder().decode(HabitJournal.self, from: data) else { return HabitJournal() }
        return journal
    }

    public static func save(_ journal: HabitJournal, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(journal) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Diferencia observada en una métrica la noche o la mañana siguiente a un día con la etiqueta.
public struct HabitImpact: Hashable, Identifiable, Sendable {
    public let tag: HabitTag
    public let metric: MetricKind
    public let withMean: Double
    public let withoutMean: Double
    public let withCount: Int
    public let withoutCount: Int
    public let pValue: Double
    public let qValue: Double
    public let effectSize: Double
    /// `true` favorable, `false` desfavorable, `nil` neutro.
    public let isFavorable: Bool?

    public var id: String { "\(tag.rawValue)-\(metric.rawValue)" }
    public var difference: Double { withMean - withoutMean }
}

/// Lo que falta para analizar una etiqueta.
public struct HabitProgress: Hashable, Identifiable, Sendable {
    public let tag: HabitTag
    public let withCount: Int
    public let withoutCount: Int
    public let need: Int

    public var id: HabitTag { tag }
    public var isReady: Bool { withCount >= need && withoutCount >= need }
}

public struct HabitReport: Hashable, Sendable {
    public var impacts: [HabitImpact] = []
    /// Etiquetas usadas, con su progreso (también las ya analizadas sin diferencia clara).
    public var progress: [HabitProgress] = []
    public var loggedDays = 0

    public init() {}
}

/// Compara la noche y la mañana siguientes a los días con y sin cada etiqueta.
///
/// - Etiqueta del día D → sueño de la noche D→D+1 (se guarda en D+1) y HRV y
///   FC en reposo de D+1.
/// - Solo días registrados; mínimo 5 días con y 5 sin la etiqueta.
/// - t de Welch con corrección de Benjamini–Hochberg entre todas las
///   comparaciones, y tamaño de efecto mínimo (d ≥ 0,4). Es una observación,
///   no una causa: el texto lo dice.
public struct HabitImpactEngine: Sendable {
    public static let outcomes: [MetricKind] = [.sleepDuration, .heartRateVariability, .restingHeartRate]

    public var minimumDays = 5
    public var minimumEffect = 0.4
    public var falseDiscoveryRate = 0.05
    /// Días hacia atrás que se miran.
    public var window = 180

    public init() {}

    public func analyze(journal: HabitJournal, history: DailyHistory, endingOn end: Date) -> HabitReport {
        let calendar = history.calendar
        let last = calendar.startOfDay(for: end)
        var report = HabitReport()
        let days = journal.loggedDays.filter { day in
            guard let distance = calendar.dateComponents([.day], from: day, to: last).day else { return false }
            return distance >= 0 && distance < window
        }
        report.loggedDays = days.count
        let used = Set(days.flatMap { journal.tags(on: $0, calendar: calendar) ?? [] })

        var candidates: [(HabitTag, MetricKind, [Double], [Double], Stats.WelchResult)] = []
        for tag in HabitTag.allCases where used.contains(tag) {
            let withDays = days.filter { journal.tags(on: $0, calendar: calendar)?.contains(tag) == true }
            let withoutDays = days.filter { journal.tags(on: $0, calendar: calendar)?.contains(tag) == false }
            report.progress.append(HabitProgress(tag: tag, withCount: withDays.count, withoutCount: withoutDays.count, need: minimumDays))
            for metric in Self.outcomes {
                let with = withDays.compactMap { next($0, metric, history) }
                let without = withoutDays.compactMap { next($0, metric, history) }
                guard with.count >= minimumDays, without.count >= minimumDays,
                      let test = Stats.welch(without, with) else { continue }
                candidates.append((tag, metric, with, without, test))
            }
        }
        let qValues = Stats.benjaminiHochberg(candidates.map(\.4.pValue))
        for (index, candidate) in candidates.enumerated() {
            let (tag, metric, with, without, test) = candidate
            guard qValues[index] < falseDiscoveryRate, abs(test.effectSize) >= minimumEffect,
                  let withMean = Stats.mean(with), let withoutMean = Stats.mean(without) else { continue }
            report.impacts.append(HabitImpact(
                tag: tag, metric: metric, withMean: withMean, withoutMean: withoutMean,
                withCount: with.count, withoutCount: without.count,
                pValue: test.pValue, qValue: qValues[index], effectSize: test.effectSize,
                isFavorable: Self.isFavorable(metric: metric, difference: withMean - withoutMean)
            ))
        }
        report.impacts.sort { abs($0.effectSize) > abs($1.effectSize) }
        return report
    }

    /// Valor de la métrica el día siguiente.
    private func next(_ day: Date, _ metric: MetricKind, _ history: DailyHistory) -> Double? {
        history.calendar.date(byAdding: .day, value: 1, to: day).flatMap { history.value(metric, on: $0) }
    }

    static func isFavorable(metric: MetricKind, difference: Double) -> Bool? {
        switch InsightEngine.favorableDirection(metric) {
        case .higher: difference > 0
        case .lower: difference < 0
        // Sueño: dormir más es favorable mientras la media esté por debajo de 9 h.
        case .within: difference > 0
        case .neutral: nil
        }
    }
}

extension HealthDataProviding {
    /// Diario frente a sueño, HRV y FC en reposo de los últimos 180 días.
    public func habitReport(journal: HabitJournal, endingOn end: Date, calendar: Calendar, engine: HabitImpactEngine = HabitImpactEngine()) async -> HabitReport {
        let last = calendar.startOfDay(for: end)
        var series: [MetricSeries] = []
        for kind in HabitImpactEngine.outcomes {
            series.append(await dailySeries(kind, days: engine.window + 1, endingOn: last))
        }
        return engine.analyze(journal: journal, history: DailyHistory(series: series, calendar: calendar), endingOn: last)
    }
}

/// Diario de ejemplo para el modo demo: alcohol los viernes,
/// estrés algunos martes. Sintético; la app lo marca como demo.
public enum DemoHabitJournal {
    public static func make(endingOn end: Date, days: Int = 70, calendar: Calendar) -> HabitJournal {
        var journal = HabitJournal()
        let last = calendar.startOfDay(for: end)
        for offset in 1..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: last) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            var tags: Set<HabitTag> = []
            if weekday == 6 { tags.insert(.alcohol) }
            if weekday == 3 && offset % 2 == 0 { tags.insert(.stress) }
            if offset % 9 == 0 { tags.insert(.lateMeal) }
            journal.set(tags, on: day, calendar: calendar)
        }
        return journal
    }
}
