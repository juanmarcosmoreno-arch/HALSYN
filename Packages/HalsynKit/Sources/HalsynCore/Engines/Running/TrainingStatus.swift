import Foundation

/// Lo que se sabe para decidir el estado de entrenamiento. Todo es opcional:
/// lo que falta no se rellena, baja la confianza.
public struct TrainingStatusInputs: Hashable, Sendable {
    /// Ritmo a pulso fijo frente a 8 semanas antes.
    public var aerobicVerdict: FixedHeartRateTrend.Verdict?
    /// Cambio del VDOT en 4 semanas y si supera su incertidumbre.
    public var vdotChange: Double?
    public var vdotChangeIsClear = false
    /// Carga de los últimos 7 días ÷ media semanal de los 28 anteriores.
    public var loadRatio: Double?
    /// Fracción del tiempo de carrera moderado o más intenso (últimos 14 días).
    public var hardShare: Double?
    /// Rodajes suaves del plan hechos más intensos, de cuántos suaves (14 días).
    public var harderThanPlanned = 0
    public var easySessions = 0
    /// Días de los últimos 7 con HRV, FC en reposo o sueño peor que tu basal
    /// (`nil` = sin datos de esa señal).
    public var hrvLowDays: Int?
    public var restingHighDays: Int?
    public var shortSleepDays: Int?
    /// Carreras en los últimos 28 días.
    public var runsLast28 = 0

    public init() {}
}

/// Estado de entrenamiento explicable (no es un diagnóstico).
public struct TrainingStatus: Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        /// Mejoras con una carga sostenible y sin señales de recuperación en contra.
        case productive
        /// Carga habitual, sin cambio claro de forma.
        case maintaining
        /// Dos o más señales de recuperación peores que tu basal.
        case recoveryNeeded
        /// La carga de la semana subió mucho frente a tu habitual.
        case highLoad
        /// Señales contradictorias, o la forma va a menos con carga normal.
        case uncertain
        /// Pocas carreras recientes y sin tendencias que mirar.
        case insufficientData
    }

    public enum Tone: String, Hashable, Sendable {
        case positive, neutral, negative
    }

    public enum Signal: Hashable, Sendable {
        case aerobic(FixedHeartRateTrend.Verdict)
        case vdot(change: Double, isClear: Bool)
        case load(ratio: Double)
        case intensity(hardShare: Double)
        case easyRunsTooHard(count: Int, of: Int)
        case hrv(lowDays: Int)
        case restingHeartRate(highDays: Int)
        case sleep(shortDays: Int)
        case consistency(runs: Int)

        public var tone: Tone {
            switch self {
            case let .aerobic(verdict):
                return verdict == .faster ? .positive : (verdict == .slower ? .negative : .neutral)
            case let .vdot(change, isClear):
                return !isClear ? .neutral : (change > 0 ? .positive : .negative)
            case let .load(ratio):
                return ratio > TrainingStatusEngine.highLoadRatio ? .negative : (ratio >= TrainingStatusEngine.lowLoadRatio ? .positive : .neutral)
            case let .intensity(share):
                return share > TrainingStatusEngine.maximumHardShare ? .negative : .positive
            case let .easyRunsTooHard(count, _):
                return count >= TrainingStatusEngine.easyRunsTooHardLimit ? .negative : .positive
            case let .hrv(days):
                return days >= TrainingStatusEngine.adverseDays ? .negative : .positive
            case let .restingHeartRate(days):
                return days >= TrainingStatusEngine.adverseDays ? .negative : .positive
            case let .sleep(days):
                return days >= TrainingStatusEngine.shortSleepDays ? .negative : .positive
            case let .consistency(runs):
                return runs >= TrainingStatusEngine.regularRuns ? .positive : .neutral
            }
        }
    }

    public enum Confidence: String, Hashable, Sendable {
        case low, medium, high
    }

    public let state: State
    public let signals: [Signal]
    public let confidence: Confidence
    /// Señales que no se pudieron evaluar por falta de datos.
    public let missing: [String]
    public let date: Date

    /// Lo que respalda el estado.
    public var supporting: [Signal] {
        switch state {
        case .recoveryNeeded, .highLoad: signals.filter { $0.tone == .negative }
        case .productive, .maintaining: signals.filter { $0.tone != .negative }
        case .uncertain, .insufficientData: []
        }
    }

    /// Lo que va en contra (o, si es incierto, todo lo que no encaja).
    public var contradicting: [Signal] {
        switch state {
        case .recoveryNeeded, .highLoad: signals.filter { $0.tone == .positive }
        case .productive, .maintaining: signals.filter { $0.tone == .negative }
        case .uncertain, .insufficientData: signals.filter { $0.tone != .neutral }
        }
    }
}

/// Estado de entrenamiento a partir de indicadores que ya calcula HÅLSYN.
///
/// Reglas, en este orden (ninguna métrica sola decide salvo la recuperación,
/// que necesita dos señales):
/// 1. **Datos insuficientes**: menos de 4 carreras en 28 días y ninguna tendencia.
/// 2. **Recuperación necesaria**: dos o más de HRV baja (≥ 3 de 7 días), FC en
///    reposo alta (≥ 3 de 7 días) o sueño corto (≥ 4 de 7 noches) frente a tu basal.
/// 3. **Carga elevada**: carga de 7 días > 1,3 × tu media semanal de las 4
///    semanas anteriores (descriptor del cambio de carga, no un predictor de lesión).
/// 4. **Progreso incierto**: la forma va a menos (ritmo a pulso fijo más lento
///    o VDOT más bajo, más allá de la incertidumbre) o las tendencias se contradicen.
/// 5. **Productivo**: mejora clara (ritmo a pulso fijo o VDOT) y como mucho una
///    señal de recuperación en contra.
/// 6. **Mantenimiento**: el resto (carga habitual, sin cambio claro).
///
/// Confianza: según cuántas de las 7 señales principales hay (≥ 6 alta, ≥ 4 media).
public enum TrainingStatusEngine {
    public static let version = "1.0"
    public static let highLoadRatio = 1.3
    public static let lowLoadRatio = 0.8
    /// Referencia de distribución polarizada (~80/20, Seiler): más de un 25 % moderado o intenso se marca.
    public static let maximumHardShare = 0.25
    public static let easyRunsTooHardLimit = 2
    public static let adverseDays = 3
    public static let shortSleepDays = 4
    public static let regularRuns = 8
    public static let minimumRuns = 4

    public static func evaluate(_ inputs: TrainingStatusInputs, date: Date = .now) -> TrainingStatus {
        var signals: [TrainingStatus.Signal] = []
        var missing: [String] = []
        var available = 0

        if let verdict = inputs.aerobicVerdict { signals.append(.aerobic(verdict)); available += 1 } else { missing.append("aerobic") }
        if let change = inputs.vdotChange { signals.append(.vdot(change: change, isClear: inputs.vdotChangeIsClear)); available += 1 } else { missing.append("vdot") }
        if let ratio = inputs.loadRatio { signals.append(.load(ratio: ratio)); available += 1 } else { missing.append("load") }
        if let share = inputs.hardShare { signals.append(.intensity(hardShare: share)); available += 1 } else { missing.append("intensity") }
        if inputs.easySessions >= 3 { signals.append(.easyRunsTooHard(count: inputs.harderThanPlanned, of: inputs.easySessions)) }
        if let days = inputs.hrvLowDays { signals.append(.hrv(lowDays: days)); available += 1 } else { missing.append("hrv") }
        if let days = inputs.restingHighDays { signals.append(.restingHeartRate(highDays: days)); available += 1 } else { missing.append("restingHeartRate") }
        if let days = inputs.shortSleepDays { signals.append(.sleep(shortDays: days)); available += 1 } else { missing.append("sleep") }
        signals.append(.consistency(runs: inputs.runsLast28))

        let confidence: TrainingStatus.Confidence = available >= 6 ? .high : (available >= 4 ? .medium : .low)
        let adverseRecovery = [
            (inputs.hrvLowDays ?? 0) >= adverseDays,
            (inputs.restingHighDays ?? 0) >= adverseDays,
            (inputs.shortSleepDays ?? 0) >= shortSleepDays,
        ].filter { $0 }.count
        let improving = inputs.aerobicVerdict == .faster || (inputs.vdotChangeIsClear && (inputs.vdotChange ?? 0) > 0)
        let declining = inputs.aerobicVerdict == .slower || (inputs.vdotChangeIsClear && (inputs.vdotChange ?? 0) < 0)
        let hasTrend = inputs.aerobicVerdict != nil || inputs.vdotChange != nil

        let state: TrainingStatus.State
        if inputs.runsLast28 < minimumRuns && !hasTrend {
            state = .insufficientData
        } else if adverseRecovery >= 2 {
            state = .recoveryNeeded
        } else if let ratio = inputs.loadRatio, ratio > highLoadRatio {
            state = .highLoad
        } else if declining {
            state = .uncertain
        } else if improving {
            state = .productive
        } else {
            state = .maintaining
        }
        return TrainingStatus(state: state, signals: signals, confidence: confidence, missing: missing, date: date)
    }
}
