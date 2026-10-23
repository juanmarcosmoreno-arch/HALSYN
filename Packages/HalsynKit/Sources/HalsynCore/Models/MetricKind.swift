import Foundation

/// Métricas que HÅLSYN entiende. El mapeo a tipos de HealthKit vive en
/// `HalsynHealthKit`; aquí solo se describe la semántica.
public enum MetricKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case heartRate
    case restingHeartRate
    case heartRateVariability
    case respiratoryRate
    case vo2Max
    case oxygenSaturation
    case steps
    case walkingRunningDistance
    case activeEnergy
    case exerciseTime
    case sleepDuration

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heartRate: "Frecuencia cardíaca"
        case .restingHeartRate: "FC en reposo"
        case .heartRateVariability: "Variabilidad cardíaca (HRV)"
        case .respiratoryRate: "Frecuencia respiratoria"
        case .vo2Max: "VO₂ máx. estimado"
        case .oxygenSaturation: "Saturación de oxígeno"
        case .steps: "Pasos"
        case .walkingRunningDistance: "Distancia a pie y corriendo"
        case .activeEnergy: "Energía activa"
        case .exerciseTime: "Tiempo de ejercicio"
        case .sleepDuration: "Sueño"
        }
    }

    public var shortTitle: String {
        switch self {
        case .heartRate: "FC"
        case .restingHeartRate: "FC reposo"
        case .heartRateVariability: "HRV"
        case .respiratoryRate: "Resp."
        case .vo2Max: "VO₂ máx."
        case .oxygenSaturation: "SpO₂"
        case .steps: "Pasos"
        case .walkingRunningDistance: "Distancia"
        case .activeEnergy: "Energía"
        case .exerciseTime: "Ejercicio"
        case .sleepDuration: "Sueño"
        }
    }

    /// Etiqueta sueca de marca cuando existe.
    public var lexicon: HalsynLexicon? {
        switch self {
        case .heartRate, .restingHeartRate, .heartRateVariability: .puls
        case .sleepDuration: .somn
        case .steps: .steg
        case .walkingRunningDistance: .rorelse
        case .vo2Max: .form
        case .exerciseTime: .tid
        default: nil
        }
    }

    public var unit: MetricUnit {
        switch self {
        case .heartRate, .restingHeartRate: .beatsPerMinute
        case .heartRateVariability: .milliseconds
        case .respiratoryRate: .breathsPerMinute
        case .vo2Max: .vo2Max
        case .oxygenSaturation: .percent
        case .steps: .count
        case .walkingRunningDistance: .meters
        case .activeEnergy: .kilocalories
        case .exerciseTime: .minutes
        case .sleepDuration: .hours
        }
    }

    /// Cómo se agrega la métrica en un día.
    public var dailyAggregation: DailyAggregation {
        switch self {
        case .steps, .walkingRunningDistance, .activeEnergy, .exerciseTime, .sleepDuration: .sum
        case .heartRate, .heartRateVariability, .respiratoryRate, .oxygenSaturation: .average
        case .restingHeartRate, .vo2Max: .latest
        }
    }

    public var systemImage: String {
        switch self {
        case .heartRate, .restingHeartRate: "heart"
        case .heartRateVariability: "waveform.path.ecg"
        case .respiratoryRate: "lungs"
        case .vo2Max: "figure.run"
        case .oxygenSaturation: "drop"
        case .steps: "shoeprints.fill"
        case .walkingRunningDistance: "point.topleft.down.to.point.bottomright.curvepath"
        case .activeEnergy: "flame"
        case .exerciseTime: "stopwatch"
        case .sleepDuration: "moon"
        }
    }
}

public enum DailyAggregation: String, Codable, Sendable {
    case sum
    case average
    case latest
}

public enum MetricUnit: String, Codable, Sendable {
    case beatsPerMinute
    case milliseconds
    case breathsPerMinute
    case vo2Max
    case percent
    case count
    case meters
    case kilocalories
    case minutes
    case hours

    public var symbol: String {
        switch self {
        case .beatsPerMinute: "lpm"
        case .milliseconds: "ms"
        case .breathsPerMinute: "rpm"
        case .vo2Max: "ml/kg·min"
        case .percent: "%"
        case .count: ""
        case .meters: "m"
        case .kilocalories: "kcal"
        case .minutes: "min"
        case .hours: "h"
        }
    }
}
