import Foundation

/// Dimensiones de la puntuación diaria de HÄLSA.
public enum HealthScoreDimension: String, CaseIterable, Codable, Identifiable, Sendable {
    case sleep
    case cardiovascular
    case movement
    case exercise
    case balance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sleep: "Sueño"
        case .cardiovascular: "Estado cardiovascular"
        case .movement: "Movimiento"
        case .exercise: "Ejercicio"
        case .balance: "Equilibrio esfuerzo-recuperación"
        }
    }

    public var systemImage: String {
        switch self {
        case .sleep: "moon"
        case .cardiovascular: "heart"
        case .movement: "shoeprints.fill"
        case .exercise: "figure.run"
        case .balance: "scalemass"
        }
    }
}

/// Pesos de cada dimensión. Son hipótesis iniciales y se pueden cambiar;
/// el motor los normaliza entre las dimensiones con datos.
public struct HealthScoreWeights: Hashable, Codable, Sendable {
    public var sleep: Double
    public var cardiovascular: Double
    public var movement: Double
    public var exercise: Double
    public var balance: Double

    public init(sleep: Double = 0.25, cardiovascular: Double = 0.25, movement: Double = 0.20, exercise: Double = 0.15, balance: Double = 0.15) {
        self.sleep = sleep
        self.cardiovascular = cardiovascular
        self.movement = movement
        self.exercise = exercise
        self.balance = balance
    }

    public static let provisional = HealthScoreWeights()

    public func weight(for dimension: HealthScoreDimension) -> Double {
        switch dimension {
        case .sleep: sleep
        case .cardiovascular: cardiovascular
        case .movement: movement
        case .exercise: exercise
        case .balance: balance
        }
    }

    public var total: Double {
        HealthScoreDimension.allCases.reduce(0) { $0 + weight(for: $1) }
    }

    /// Pesos no negativos y con suma positiva.
    public var isValid: Bool {
        HealthScoreDimension.allCases.allSatisfy { weight(for: $0) >= 0 } && total > 0
    }
}

/// Efecto de un factor sobre la puntuación.
public enum ScoreImpact: String, Codable, Sendable {
    case positive
    case neutral
    case negative
}

/// Factor explicable que contribuyó a la puntuación. Los valores son datos;
/// la interfaz compone el texto localizado.
public struct ScoreFactor: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Horas dormidas la noche que termina ese día.
        case sleepDuration(hours: Double)
        /// Diferencia de FC en reposo frente a la media personal (lpm).
        case restingHeartRate(deltaFromBaseline: Double)
        /// Diferencia relativa de HRV frente a la media personal (fracción).
        case heartRateVariability(relativeDeltaFromBaseline: Double)
        /// Media diaria de pasos en los 7 días completos anteriores.
        case averageSteps(perDay: Double)
        /// Minutos de ejercicio en los 7 días completos anteriores.
        case weeklyExercise(minutes: Double)
        /// Carga aguda / crónica de minutos de ejercicio.
        case trainingLoadRatio(Double)
    }

    public let kind: Kind
    public let dimension: HealthScoreDimension
    public let impact: ScoreImpact

    public init(kind: Kind, dimension: HealthScoreDimension, impact: ScoreImpact) {
        self.kind = kind
        self.dimension = dimension
        self.impact = impact
    }
}

/// Puntuación de una dimensión, o el motivo por el que no se calculó.
public struct DimensionScore: Hashable, Identifiable, Sendable {
    public enum MissingReason: String, Hashable, Sendable {
        /// No hay datos de esta dimensión en el periodo.
        case noData
        /// Hay datos, pero no suficiente historial para compararlos con tu media.
        case insufficientHistory
    }

    public let dimension: HealthScoreDimension
    public let score: Int?
    /// Peso configurado (sin normalizar).
    public let weight: Double
    public let missingReason: MissingReason?

    public var id: HealthScoreDimension { dimension }

    public init(dimension: HealthScoreDimension, score: Int?, weight: Double, missingReason: MissingReason?) {
        self.dimension = dimension
        self.score = score
        self.weight = weight
        self.missingReason = score == nil ? (missingReason ?? .noData) : nil
    }
}

public enum ScoreConfidence: String, Hashable, Sendable {
    case low, medium, high
}

/// Desglose transparente de una puntuación diaria.
public struct HealthScoreBreakdown: Hashable, Sendable {
    public let dimensions: [DimensionScore]
    /// Fracción (0–1) del peso total que tenía datos.
    public let coverage: Double
    public let confidence: ScoreConfidence
    public let factors: [ScoreFactor]
    public let engineVersion: String

    public init(dimensions: [DimensionScore], coverage: Double, confidence: ScoreConfidence, factors: [ScoreFactor], engineVersion: String) {
        self.dimensions = dimensions
        self.coverage = coverage
        self.confidence = confidence
        self.factors = factors
        self.engineVersion = engineVersion
    }
}
