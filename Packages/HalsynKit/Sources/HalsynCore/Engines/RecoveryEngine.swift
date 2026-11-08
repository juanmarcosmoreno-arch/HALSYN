import Foundation

/// Componentes de la recuperación estimada de VILA.
public enum RecoveryComponentKind: String, CaseIterable, Hashable, Sendable {
    case heartRateVariability
    case restingHeartRate
    case sleep
    case recentLoad

    public var title: String {
        switch self {
        case .heartRateVariability: "HRV frente a tu media"
        case .restingHeartRate: "FC en reposo frente a tu media"
        case .sleep: "Sueño de anoche"
        case .recentLoad: "Esfuerzo de los últimos 3 días"
        }
    }

    public var systemImage: String {
        switch self {
        case .heartRateVariability: "waveform.path.ecg"
        case .restingHeartRate: "heart"
        case .sleep: "moon"
        case .recentLoad: "figure.run"
        }
    }
}

/// Un componente con su puntuación o el motivo por el que falta.
public struct RecoveryComponent: Hashable, Identifiable, Sendable {
    public let kind: RecoveryComponentKind
    public let score: Int?
    public let weight: Double
    public let missingReason: DimensionScore.MissingReason?
    /// Valor que explica el componente:
    /// HRV → diferencia relativa (fracción); FC reposo → diferencia en lpm;
    /// sueño → horas; carga → cociente 3 días / media de 28.
    public let detail: Double?
    public let impact: ScoreImpact
    /// `true` si el valor es del día anterior (aún no hay medición de hoy).
    public let usesPreviousDay: Bool
    /// Valor usado (HRV: media de 3 días; FC: la del día; sueño: horas;
    /// carga: minutos diarios de los últimos 3 días).
    public var recentValue: Double?
    /// Tu línea basal (mediana de 28 días; carga: media diaria de 28 días).
    public var baselineValue: Double?
    /// Días con dato en la línea basal.
    public var baselineDays: Int = 0
    /// Solo HRV: la medición del día, sin promediar.
    public var singleDayValue: Double?
    /// Solo HRV: días con dato en la ventana de 7.
    public var windowDays: Int = 0
    /// Solo HRV: media de 7 días frente a la de los 7 anteriores (fracción).
    public var weeklyTrend: Double?
    /// Solo sueño: la noche tiene un registro corto que parece incompleto y no se usó.
    public var possiblyIncomplete = false
    /// Solo sueño: siesta del día anterior que no cuenta como sueño de la noche (horas).
    public var napHours: Double?
    /// Desviación favorable estandarizada (HRV y FC en reposo).
    public var detailZ: Double?

    public var id: RecoveryComponentKind { kind }
}

/// Aviso que acompaña a la recuperación (no cambia el cálculo salvo la enfermedad).
public enum RecoveryWarning: Hashable, Sendable {
    /// HRV muy por encima de tu basal (z > 2): puede ser normal o cansancio
    /// acumulado (saturación parasimpática); no suma más que +1 desviación.
    case hrvUnusuallyHigh
    /// Enfermedad, fiebre o lesión en curso: la recuperación se limita a 50.
    case illness
    /// Sesión intensa hace menos de 24 h.
    case recentHardSession(hours: Int)
    /// La noche parece incompleta: el sueño no entra.
    case incompleteSleep
    /// HRV con menos de 4 días en la ventana de 7.
    case shortHRVWindow
    /// Algún valor es de ayer (aún no hay medición de hoy).
    case usesYesterday
}

/// Contexto opcional que no viene de las series diarias.
public struct RecoveryContext: Hashable, Sendable {
    public var activeIllness: Bool
    public var hoursSinceHardSession: Double?

    public init(activeIllness: Bool = false, hoursSinceHardSession: Double? = nil) {
        self.activeIllness = activeIllness
        self.hoursSinceHardSession = hoursSinceHardSession
    }
}

/// Contexto por día que registra la app (eventos de salud, sesiones intensas).
/// Lo consultan todos los cálculos de recuperación, también los de los
/// proveedores de datos, para que el valor sea el mismo en cada pantalla.
public struct RecoveryContextSource: Hashable, Sendable {
    /// Días con enfermedad, fiebre o lesión registradas.
    public var illnessDays: Set<Date>
    /// Fin de las sesiones intensas (tempo o más) recientes.
    public var hardSessionEnds: [Date]

    public init(illnessDays: Set<Date> = [], hardSessionEnds: [Date] = []) {
        self.illnessDays = illnessDays
        self.hardSessionEnds = hardSessionEnds
    }

    /// Las horas desde la sesión intensa se cuentan hasta las 8:00 de ese día
    /// (la recuperación es la de la mañana).
    public func context(for day: Date, calendar: Calendar) -> RecoveryContext {
        let start = calendar.startOfDay(for: day)
        let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: start) ?? start
        let last = hardSessionEnds.filter { $0 <= morning }.max()
        return RecoveryContext(activeIllness: illnessDays.contains(start), hoursSinceHardSession: last.map { morning.timeIntervalSince($0) / 3600 })
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = RecoveryContextSource()

    /// El contexto vigente (vacío salvo que la app lo actualice).
    public static var current: RecoveryContextSource {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Recuperación estimada (0–100) de un día, con su desglose.
public struct RecoveryEstimate: Hashable, Identifiable, Sendable {
    public let day: Date
    public let value: Int?
    public let components: [RecoveryComponent]
    public let coverage: Double
    public let confidence: ScoreConfidence
    public let origin: DataOrigin
    public let engineVersion: String
    public var warnings: [RecoveryWarning] = []
    /// Media ponderada antes de la agregación prudente y del límite por enfermedad.
    public var weightedMean: Double?

    public var id: Date { day }

    public var band: ScoreBand? { value.map { ScoreBand(score: $0) } }

    public var dailyScore: DailyScore? {
        value.map { DailyScore(day: day, value: $0, weeklyChange: nil, origin: origin) }
    }
}

public struct RecoveryConfiguration: Sendable {
    public var weights: [RecoveryComponentKind: Double]
    public var minimumCoverage: Double
    public var baselineDays: Int
    public var minimumBaselineDays: Int
    public var recommendedSleep: ClosedRange<Double>

    public init(
        weights: [RecoveryComponentKind: Double] = [.heartRateVariability: 0.35, .restingHeartRate: 0.25, .sleep: 0.25, .recentLoad: 0.15],
        minimumCoverage: Double = 0.6,
        baselineDays: Int = 28,
        minimumBaselineDays: Int = 7,
        recommendedSleep: ClosedRange<Double> = 7...9
    ) {
        self.weights = weights
        self.minimumCoverage = minimumCoverage
        self.baselineDays = baselineDays
        self.minimumBaselineDays = minimumBaselineDays
        self.recommendedSleep = recommendedSleep
    }

    public func weight(_ kind: RecoveryComponentKind) -> Double { max(0, weights[kind] ?? 0) }
}

/// Motor de recuperación estimada de VILA.
///
/// Reglas (Documentation/RECOVERY.md, versión 0.4):
/// - **0.4**: una HRV por encima de tu basal suma como mucho +1 desviación (87,5
///   puntos); por encima de +2 se avisa. El total es 0,75 × media ponderada +
///   0,25 × el componente más bajo, para que una señal adversa no quede
///   compensada del todo por las favorables. Con enfermedad, fiebre o lesión en
///   curso, como mucho 50. Avisos explícitos (sesión intensa reciente, noche
///   incompleta, ventana de HRV corta, valores de ayer).
/// - **Línea basal robusta**: mediana y MAD × 1,4826 (equivalente a una
///   desviación típica sin que un valor raro la mueva) de los 28 días
///   anteriores (mínimo 7).
/// - **HRV**: media móvil de 7 días del logaritmo (ln SDNN; mínimo 4 días con
///   dato, si no los que haya y baja la confianza), como recomiendan Plews et al.
///   (2012, 2013) para no interpretar una sola medición; frente a la línea basal
///   (ln) de los 28 días previos a esa ventana. Hasta la 0.2 era la media
///   aritmética de 3 días, que dejaba que dos días altos taparan uno normal.
/// - **FC en reposo**: la del día (o la de ayer, y se indica) frente a su línea basal.
/// - En la línea basal = 75; mejor sube hasta 100 (+2); peor baja hasta 15 (−3).
/// - **Sueño** principal de la noche que termina ese día (sin siestas, si se
///   conocen las noches; una noche con registro de menos de 3 h cuando lo
///   habitual son 5 h o más se trata como dato incompleto y no se usa): el menor entre la curva de
///   7–9 h (la de HÄLSA) y la comparación con **tu sueño habitual** (mediana
///   de 28 noches): sin penalización hasta 30 min por debajo, y 25 puntos
///   menos por cada hora más.
/// - **Esfuerzo reciente**: minutos de ejercicio de los 3 días anteriores frente
///   a tu media de 28 días. Igual o por debajo de lo habitual = 100; el doble y
///   medio o más = 40.
/// - Hace falta al menos HRV o FC en reposo (una señal fisiológica) y el 60 % del peso.
/// - Es una estimación orientativa, no un diagnóstico: no dice si estás
///   médicamente recuperado.
public struct RecoveryEngine: Sendable {
    public static let version = "0.4"
    /// Peso del componente más bajo en la agregación prudente.
    public static let limitingWeight = 0.25
    public static let illnessCap = 50
    public static let hrvWindowDays = 7
    public static let hrvMinimumWindowDays = 4
    public static let inputs: [MetricKind] = [.heartRateVariability, .restingHeartRate, .sleepDuration, .exerciseTime]

    public let configuration: RecoveryConfiguration

    public init(configuration: RecoveryConfiguration = RecoveryConfiguration()) {
        self.configuration = configuration
    }

    /// Línea basal de 28 días antes de la ventana de 7 de la HRV.
    public var historyDaysNeeded: Int { configuration.baselineDays + Self.hrvWindowDays }

    /// - `nights`: noches por día (opcional) para separar siestas y registros incompletos.
    /// - `context`: si falta, el de `RecoveryContextSource.current` para ese día.
    public func evaluate(day: Date, history: DailyHistory, origin: DataOrigin, nights: [Date: SleepNight] = [:], context explicitContext: RecoveryContext? = nil) -> RecoveryEstimate {
        let start = history.calendar.startOfDay(for: day)
        let context = explicitContext ?? RecoveryContextSource.current.context(for: start, calendar: history.calendar)
        let components = RecoveryComponentKind.allCases.map { component($0, day: start, history: history, nights: nights) }
        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let available = components.filter { $0.score != nil && $0.weight > 0 }
        let availableWeight = available.reduce(0) { $0 + $1.weight }
        let coverage = totalWeight > 0 ? availableWeight / totalWeight : 0
        let hasPhysiology = available.contains { $0.kind == .heartRateVariability || $0.kind == .restingHeartRate }

        var value: Int?
        var weightedMean: Double?
        if hasPhysiology, coverage >= configuration.minimumCoverage, availableWeight > 0 {
            let mean = available.reduce(0.0) { $0 + Double($1.score ?? 0) * $1.weight } / availableWeight
            weightedMean = mean
            let lowest = Double(available.compactMap(\.score).min() ?? 0)
            var combined = (1 - Self.limitingWeight) * mean + Self.limitingWeight * lowest
            if context.activeIllness { combined = min(combined, Double(Self.illnessCap)) }
            value = Int(combined.rounded())
        }

        let depth = [MetricKind.heartRateVariability, .restingHeartRate]
            .map { history.values($0, daysBefore: start, count: configuration.baselineDays).count }
            .max() ?? 0
        let usesYesterday = available.contains(where: \.usesPreviousDay)
        let confidence: ScoreConfidence
        let shortHRVWindow = available.contains { $0.kind == .heartRateVariability && $0.windowDays < Self.hrvMinimumWindowDays }
        if coverage >= 0.9 && depth >= 14 && !usesYesterday && !shortHRVWindow {
            confidence = .high
        } else if coverage >= 0.75 {
            confidence = .medium
        } else {
            confidence = .low
        }
        var estimate = RecoveryEstimate(day: start, value: value, components: components, coverage: coverage, confidence: confidence, origin: origin, engineVersion: Self.version)
        estimate.weightedMean = weightedMean
        var warnings: [RecoveryWarning] = []
        if components.contains(where: { $0.kind == .heartRateVariability && ($0.detailZ ?? 0) > 2 }) { warnings.append(.hrvUnusuallyHigh) }
        if context.activeIllness { warnings.append(.illness) }
        if let hours = context.hoursSinceHardSession, hours < 24 { warnings.append(.recentHardSession(hours: Int(hours.rounded()))) }
        if components.contains(where: \.possiblyIncomplete) { warnings.append(.incompleteSleep) }
        if shortHRVWindow { warnings.append(.shortHRVWindow) }
        if usesYesterday { warnings.append(.usesYesterday) }
        estimate.warnings = warnings
        return estimate
    }

    private func component(_ kind: RecoveryComponentKind, day: Date, history: DailyHistory, nights: [Date: SleepNight]) -> RecoveryComponent {
        let weight = configuration.weight(kind)
        func missing(_ reason: DimensionScore.MissingReason) -> RecoveryComponent {
            RecoveryComponent(kind: kind, score: nil, weight: weight, missingReason: reason, detail: nil, impact: .neutral, usesPreviousDay: false)
        }
        switch kind {
        case .heartRateVariability, .restingHeartRate:
            let metric: MetricKind = kind == .heartRateVariability ? .heartRateVariability : .restingHeartRate
            var reference = day
            var usesPrevious = false
            var value = history.value(metric, on: day)
            if value == nil, let yesterday = history.calendar.date(byAdding: .day, value: -1, to: day) {
                value = history.value(metric, on: yesterday)
                reference = yesterday
                usesPrevious = value != nil
            }
            guard var value else { return missing(.noData) }
            var baselineEnd = reference
            var windowCount = 1
            var trend: Double?
            var baselineValues: [Double]
            if metric == .heartRateVariability {
                // Media móvil de 7 días en escala logarítmica (Plews et al.).
                func lnValues(endingOn end: Date, count: Int) -> [Double] {
                    let raw: [Double] = (0..<count).compactMap { offset -> Double? in
                        history.calendar.date(byAdding: .day, value: -offset, to: end).flatMap { history.value(metric, on: $0) }
                    }
                    return raw.filter { $0 > 0 }.map { Foundation.log($0) }
                }
                let window = lnValues(endingOn: reference, count: Self.hrvWindowDays)
                windowCount = window.count
                if window.isEmpty {
                    value = Foundation.log(max(value, 1))
                } else {
                    value = window.reduce(0, +) / Double(window.count)
                }
                if let previousEnd = history.calendar.date(byAdding: .day, value: -Self.hrvWindowDays, to: reference) {
                    let previous = lnValues(endingOn: previousEnd, count: Self.hrvWindowDays)
                    if previous.count >= Self.hrvMinimumWindowDays, window.count >= Self.hrvMinimumWindowDays {
                        let previousMean = previous.reduce(0, +) / Double(previous.count)
                        trend = Foundation.exp(value - previousMean) - 1
                    }
                }
                baselineEnd = history.calendar.date(byAdding: .day, value: -(Self.hrvWindowDays - 1), to: reference) ?? reference
                baselineValues = history.values(metric, daysBefore: baselineEnd, count: configuration.baselineDays).filter { $0 > 0 }.map { Foundation.log($0) }
            } else {
                baselineValues = history.values(metric, daysBefore: baselineEnd, count: configuration.baselineDays)
            }
            guard baselineValues.count >= configuration.minimumBaselineDays else { return missing(.insufficientHistory) }
            let robust = RobustBaseline(baselineValues)
            let z: Double
            let detail: Double
            if metric == .heartRateVariability {
                // En ln: la escala mínima equivale a un 5 % de variación.
                z = (value - robust.median) / max(robust.scale, 0.05)
                detail = Foundation.exp(value - robust.median) - 1
            } else {
                // FC en reposo más baja de lo habitual es favorable: se invierte el signo.
                z = -(value - robust.median) / max(robust.scale, 2)
                detail = value - robust.median
            }
            let impact: ScoreImpact = z <= -1 ? .negative : (z >= 0.5 ? .positive : .neutral)
            // Una HRV muy alta no es necesariamente mejor (Plews et al.): suma como mucho +1 desviación.
            let scored = metric == .heartRateVariability ? min(z, 1) : z
            var result = RecoveryComponent(kind: kind, score: Int(Self.baselineScore(z: scored).rounded()), weight: weight, missingReason: nil, detail: detail, impact: impact, usesPreviousDay: usesPrevious)
            result.detailZ = z
            if metric == .heartRateVariability {
                result.recentValue = Foundation.exp(value)
                result.baselineValue = Foundation.exp(robust.median)
                result.singleDayValue = history.value(metric, on: reference)
                result.windowDays = windowCount
                result.weeklyTrend = trend
            } else {
                result.recentValue = value
                result.baselineValue = robust.median
            }
            result.baselineDays = baselineValues.count
            return result
        case .sleep:
            let range = configuration.recommendedSleep
            // Con las noches: solo el sueño principal (las siestas aparte).
            var hours = history.value(.sleepDuration, on: day)
            var napHours: Double?
            var habitual = history.values(.sleepDuration, daysBefore: day, count: configuration.baselineDays)
            if let night = nights[day] {
                hours = night.mainAsleep / 3600
                if night.napAsleep >= 600 { napHours = night.napAsleep / 3600 }
                let previousNights: [SleepNight] = (1...configuration.baselineDays).compactMap { offset in
                    history.calendar.date(byAdding: .day, value: -offset, to: day).flatMap { nights[$0] }
                }
                let previous = previousNights.filter { !$0.flags.contains(.shortRecord) }.map { $0.mainAsleep / 3600 }
                if previous.count >= configuration.minimumBaselineDays { habitual = previous }
                // Registro corto (< 3 h) cuando lo habitual son 5 h o más: probablemente incompleto.
                if night.flags.contains(.shortRecord), habitual.count >= configuration.minimumBaselineDays, RobustBaseline(habitual).median >= 5 {
                    var incomplete = missing(.noData)
                    incomplete.possiblyIncomplete = true
                    incomplete.recentValue = night.mainAsleep / 3600
                    return incomplete
                }
            }
            guard let hours else { return missing(.noData) }
            var score = HealthScoreEngine.sleepScore(hours: hours, recommended: range)
            var belowHabit = false
            var habitualMedian: Double?
            if habitual.count >= configuration.minimumBaselineDays {
                let median = RobustBaseline(habitual).median
                habitualMedian = median
                let personal = Self.personalSleepScore(hours: hours, habitual: median)
                belowHabit = personal < 100
                score = min(score, personal)
            }
            let impact: ScoreImpact = range.contains(hours) && !belowHabit ? .positive : (hours < range.lowerBound - 1 || score < 60 ? .negative : .neutral)
            var result = RecoveryComponent(kind: kind, score: Int(score.rounded()), weight: weight, missingReason: nil, detail: hours, impact: impact, usesPreviousDay: false)
            result.recentValue = hours
            result.baselineValue = habitualMedian
            result.baselineDays = habitual.count
            result.napHours = napHours
            return result
        case .recentLoad:
            let chronicValues = history.values(.exerciseTime, daysBefore: day, count: configuration.baselineDays)
            guard !chronicValues.isEmpty else { return missing(.noData) }
            guard chronicValues.count >= 14 else { return missing(.insufficientHistory) }
            let chronic = chronicValues.reduce(0, +) / Double(configuration.baselineDays)
            guard chronic >= 5 else { return missing(.insufficientHistory) }
            // Los días sin registro cuentan como 0 min (suma de esfuerzo).
            let acute = history.values(.exerciseTime, daysBefore: day, count: 3).reduce(0, +) / 3
            let ratio = acute / chronic
            let impact: ScoreImpact = ratio > 1.5 ? .negative : (ratio <= 1 ? .positive : .neutral)
            var result = RecoveryComponent(kind: kind, score: Int(Self.recentLoadScore(ratio: ratio).rounded()), weight: weight, missingReason: nil, detail: ratio, impact: impact, usesPreviousDay: false)
            result.recentValue = acute
            result.baselineValue = chronic
            result.baselineDays = chronicValues.count
            return result
        }
    }

    // MARK: Curvas (públicas para tests y documentación)

    /// `z` = desviación favorable en desviaciones típicas (positivo = mejor que tu media).
    /// 75 en tu media; +2 → 100; −3 → 15 (lineal por tramos).
    public static func baselineScore(z: Double) -> Double {
        let clamped = min(max(z, -3), 2)
        return clamped >= 0 ? 75 + 12.5 * clamped : 75 + 20 * clamped
    }

    /// Sueño frente a tu sueño habitual: 100 hasta 30 min por debajo; luego
    /// 25 puntos menos por hora, sin bajar de 30.
    public static func personalSleepScore(hours: Double, habitual: Double) -> Double {
        let shortfall = habitual - 0.5 - hours
        guard shortfall > 0 else { return 100 }
        return max(30, 100 - 25 * shortfall)
    }

    /// 100 hasta 1 (lo habitual o menos); baja lineal hasta 40 en 2,5.
    public static func recentLoadScore(ratio: Double) -> Double {
        if ratio <= 1 { return 100 }
        if ratio >= 2.5 { return 40 }
        return 100 - (ratio - 1) / 1.5 * 60
    }
}

extension HealthDataProviding {
    /// Recuperación de los `days` días que terminan en `end`, con el mismo motor
    /// para demo y Apple Health. Incluye los días sin estimación (`value == nil`).
    public func computeRecovery(
        endingOn end: Date,
        days: Int,
        engine: RecoveryEngine = RecoveryEngine(),
        calendar: Calendar,
        origin: DataOrigin
    ) async -> [RecoveryEstimate] {
        guard days > 0 else { return [] }
        let lastDay = calendar.startOfDay(for: end)
        let fetchDays = days + engine.historyDaysNeeded
        var series: [MetricSeries] = []
        for kind in RecoveryEngine.inputs {
            series.append(await dailySeries(kind, days: fetchDays, endingOn: lastDay))
        }
        let history = DailyHistory(series: series, calendar: calendar)
        let nightList = await sleepNights(endingOn: lastDay, days: fetchDays)
        let nights = Dictionary(nightList.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { _, last in last })
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: lastDay).map { engine.evaluate(day: $0, history: history, origin: origin, nights: nights) }
        }
    }
}

/// Línea basal robusta: mediana y MAD escalada (× 1,4826, equivalente a la
/// desviación típica en una normal). Un valor aislado no la mueve.
public struct RobustBaseline: Hashable, Sendable {
    public let median: Double
    public let scale: Double

    public init(_ values: [Double]) {
        let sorted = values.sorted()
        func medianOf(_ items: [Double]) -> Double {
            guard !items.isEmpty else { return 0 }
            let middle = items.count / 2
            return items.count.isMultiple(of: 2) ? (items[middle - 1] + items[middle]) / 2 : items[middle]
        }
        let center = medianOf(sorted)
        median = center
        scale = 1.4826 * medianOf(sorted.map { abs($0 - center) }.sorted())
    }
}
