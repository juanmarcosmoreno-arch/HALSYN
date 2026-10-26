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
    // Cuerpo (balanzas que escriben en Salud, p. ej. Xiaomi vía Zepp Life).
    case bodyMass
    case bodyFatPercentage
    case leanBodyMass
    /// Temperatura de muñeca durante el sueño (Apple Watch Series 8 o posterior).
    case wristTemperature
    /// Minutos con luz natural (Apple Watch, watchOS 10 o posterior).
    case timeInDaylight

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
        case .bodyMass: "Peso"
        case .bodyFatPercentage: "Grasa corporal"
        case .leanBodyMass: "Masa magra"
        case .wristTemperature: "Temperatura de muñeca"
        case .timeInDaylight: "Luz del día"
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
        case .bodyMass: "Peso"
        case .bodyFatPercentage: "Grasa"
        case .leanBodyMass: "Masa magra"
        case .wristTemperature: "Temp."
        case .timeInDaylight: "Luz"
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
        case .bodyMass, .bodyFatPercentage, .leanBodyMass: .kropp
        case .exerciseTime: .tid
        case .timeInDaylight: .ljus
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
        case .bodyMass, .leanBodyMass: .kilograms
        case .bodyFatPercentage: .percent
        case .wristTemperature: .celsius
        case .timeInDaylight: .minutes
        }
    }

    /// Cómo se agrega la métrica en un día.
    public var dailyAggregation: DailyAggregation {
        switch self {
        case .steps, .walkingRunningDistance, .activeEnergy, .exerciseTime, .sleepDuration, .timeInDaylight: .sum
        case .heartRate, .heartRateVariability, .respiratoryRate, .oxygenSaturation, .wristTemperature: .average
        case .restingHeartRate, .vo2Max, .bodyMass, .bodyFatPercentage, .leanBodyMass: .latest
        }
    }

    /// Días hacia atrás en los que se busca el último valor de las métricas
    /// `.latest`. El VO₂ máx. se estima con poca frecuencia; la FC en reposo, a diario.
    public var latestLookbackDays: Int {
        switch self {
        case .vo2Max: 120
        // La gente no se pesa a diario.
        case .bodyMass, .bodyFatPercentage, .leanBodyMass: 60
        default: 1
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
        case .bodyMass: "scalemass"
        case .bodyFatPercentage: "percent"
        case .leanBodyMass: "figure.strengthtraining.traditional"
        case .wristTemperature: "thermometer.medium"
        case .timeInDaylight: "sun.max"
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
    case kilograms
    case celsius

    public var symbol: String {
        switch self {
        case .beatsPerMinute: "lpm"
        case .milliseconds: "ms"
        case .breathsPerMinute: "resp/min"
        case .vo2Max: "ml/kg·min"
        case .percent: "%"
        case .count: ""
        case .meters: "m"
        case .kilocalories: "kcal"
        case .minutes: "min"
        case .hours: "h"
        case .kilograms: "kg"
        case .celsius: "°C"
        }
    }
}
