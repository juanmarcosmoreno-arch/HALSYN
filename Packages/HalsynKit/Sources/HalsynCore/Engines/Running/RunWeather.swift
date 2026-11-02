import Foundation

/// Tiempo que hacía durante un entrenamiento al aire libre.
public struct RunWeather: Hashable, Codable, Sendable {
    public enum Source: String, Hashable, Codable, Sendable {
        /// Guardado con el entrenamiento en Salud (lo hace la app Entreno).
        case health
        /// Consultado a WeatherKit para la hora y el lugar de salida.
        case weatherKit
    }

    /// Temperatura del aire en °C.
    public let temperature: Double
    /// Humedad relativa 0…1, si se conoce.
    public let humidity: Double?
    public let source: Source

    public init(temperature: Double, humidity: Double?, source: Source) {
        self.temperature = temperature
        self.humidity = humidity.map { min(max($0 > 1.5 ? $0 / 100 : $0, 0), 1) }
        self.source = source
    }

    public var heat: HeatStress { HeatStress(temperature: temperature, humidity: humidity) }
}

/// Cuánto pesa el calor en una carrera. Pauta orientativa de HÅLSYN basada en
/// Ely et al. 2007 (el rendimiento en maratón empeora de forma progresiva por
/// encima de unos 10 °C y más en los corredores menos rápidos): la humedad
/// alta suma porque dificulta enfriarse con el sudor.
public enum HeatStress: Int, Comparable, Hashable, Sendable {
    case cool, mild, warm, hot

    public init(temperature: Double, humidity: Double?) {
        let humid = (humidity ?? 0) >= 0.75
        switch temperature {
        case 25...: self = .hot
        case 20..<25: self = humid ? .hot : .warm
        case 15..<20: self = humid ? .warm : .mild
        default: self = .cool
        }
    }

    public static func < (lhs: HeatStress, rhs: HeatStress) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .cool: "Fresco: buenas condiciones"
        case .mild: "Templado"
        case .warm: "Calor: cuenta en el ritmo"
        case .hot: "Mucho calor: no compares el ritmo"
        }
    }

    public var explanation: String {
        switch self {
        case .cool:
            "Con fresco el cuerpo se enfría bien: es cuando el ritmo y el pulso reflejan mejor tu forma."
        case .mild:
            "Condiciones razonables. Si es una carrera larga o hay mucho sol, el pulso puede subir un poco."
        case .warm:
            "Con calor el corazón trabaja más para enfriarte: el pulso sube y el ritmo baja aunque estés igual de en forma. Compáralo con días parecidos, no con uno fresco."
        case .hot:
            "Con mucho calor o humedad, ir más lento y con el pulso más alto es lo normal. No lo tomes como una mala carrera, bebe y baja el ritmo; en días así lo mejor es correr por tiempo o por esfuerzo."
        }
    }
}
