import Foundation

/// Lectura de potencia de un medidor (vatios) durante un intervalo.
public struct PowerSample: Hashable, Sendable {
    public let start: Date
    public let end: Date
    public let watts: Double

    public init(start: Date, end: Date, watts: Double) {
        self.start = start
        self.end = max(end, start)
        self.watts = watts
    }
}

/// Zonas de potencia de Coggan (7 zonas, en porcentaje del FTP).
/// Allen H, Coggan AR, McGregor S. Training and Racing with a Power Meter.
public struct PowerZone: Hashable, Identifiable, Sendable {
    public let index: Int
    /// Límite inferior como fracción del FTP (0 en Z1).
    public let lowerFraction: Double
    /// Límite superior como fracción del FTP (`nil` en Z7, sin techo).
    public let upperFraction: Double?

    public var id: Int { index }

    public var name: String {
        switch index {
        case 1: "Recuperación activa"
        case 2: "Resistencia"
        case 3: "Tempo"
        case 4: "Umbral"
        case 5: "VO₂max"
        case 6: "Capacidad anaeróbica"
        default: "Neuromuscular"
        }
    }

    /// Rango en vatios para un FTP dado (techo `nil` en Z7).
    public func watts(ftp: Double) -> (lower: Double, upper: Double?) {
        (lowerFraction * ftp, upperFraction.map { $0 * ftp })
    }
}

public enum PowerZones {
    /// Techos de Z1…Z6 en fracción del FTP: 55, 75, 90, 105, 120 y 150 %.
    public static let upperFractions: [Double] = [0.55, 0.75, 0.90, 1.05, 1.20, 1.50]

    public static let zones: [PowerZone] = (1...7).map { index in
        PowerZone(
            index: index,
            lowerFraction: index == 1 ? 0 : upperFractions[index - 2],
            upperFraction: index <= upperFractions.count ? upperFractions[index - 1] : nil
        )
    }

    /// Zona 1…7 de una potencia; `nil` sin FTP válido.
    public static func zone(for watts: Double, ftp: Double) -> Int? {
        guard ftp > 0, watts >= 0 else { return nil }
        let fraction = watts / ftp
        return (upperFractions.firstIndex { fraction <= $0 } ?? upperFractions.count) + 1
    }
}

/// Resumen de potencia de una salida.
public struct PowerSummary: Hashable, Sendable {
    /// Segundos con lectura de potencia (sin pausas ni cortes del sensor).
    public let duration: TimeInterval
    public let averagePower: Double
    public let maxPower: Double
    /// Potencia normalizada (NP); `nil` con menos de `PowerAnalysis.minimumNormalizedDuration` segundos.
    public let normalizedPower: Double?
    /// Mejor media de 20 minutos seguidos; `nil` si no hubo 20 minutos con datos.
    public let best20Minutes: Double?
    /// Mejor media de 5 minutos seguidos.
    public let best5Minutes: Double?

    /// Factor de intensidad: NP / FTP.
    public func intensityFactor(ftp: Double) -> Double? {
        guard ftp > 0, let normalizedPower else { return nil }
        return normalizedPower / ftp
    }

    /// Training Stress Score: (s × NP × IF) / (FTP × 3600) × 100.
    /// Una hora exactamente al FTP = 100.
    public func trainingStressScore(ftp: Double) -> Double? {
        guard ftp > 0, let normalizedPower, let intensity = intensityFactor(ftp: ftp) else { return nil }
        return duration * normalizedPower * intensity / (ftp * 3600) * 100
    }
}

/// Cálculos de potencia sobre las lecturas guardadas en Apple Health.
///
/// Las lecturas se pasan a una serie de un valor por segundo: cada lectura vale
/// hasta la siguiente; si entre el final de una lectura y la siguiente pasan más
/// de `maxGap` segundos (pausa o sensor desconectado) la serie se corta y ese hueco no cuenta, ni
/// como cero ni como potencia. Los ceros reales (dejar de pedalear) sí cuentan,
/// como en el método original de la potencia normalizada.
public enum PowerAnalysis {
    public static let maxGap: TimeInterval = 5
    /// Ventana móvil de la potencia normalizada.
    public static let normalizedWindow = 30
    public static let minimumNormalizedDuration: TimeInterval = 300
    /// Lecturas imposibles para una persona se descartan.
    public static let plausibleWatts: ClosedRange<Double> = 0...2500

    /// Tramos continuos de un valor por segundo.
    public static func secondsSeries(_ samples: [PowerSample]) -> [[Double]] {
        let sorted = samples
            .filter { $0.watts.isFinite && plausibleWatts.contains($0.watts) }
            .sorted { $0.start < $1.start }
        var segments: [[Double]] = []
        var current: [Double] = []
        var carry: TimeInterval = 0
        for (index, sample) in sorted.enumerated() {
            let ownSpan = max(1, sample.end.timeIntervalSince(sample.start))
            var span = ownSpan
            var breaksAfter = false
            if index + 1 < sorted.count {
                // El hueco se mide desde el final de la lectura: lecturas largas
                // seguidas (p. ej. de 10 s o 60 s) no cortan la serie.
                let next = sorted[index + 1]
                if next.start.timeIntervalSince(sample.end) <= maxGap {
                    span = max(0, next.start.timeIntervalSince(sample.start))
                } else {
                    breaksAfter = true
                }
            }
            carry += span
            let whole = Int(carry)
            carry -= Double(whole)
            current.append(contentsOf: repeatElement(sample.watts, count: whole))
            if breaksAfter {
                if !current.isEmpty { segments.append(current) }
                current = []
                carry = 0
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    public static func summary(_ samples: [PowerSample]) -> PowerSummary? {
        summary(segments: secondsSeries(samples))
    }

    public static func summary(segments: [[Double]]) -> PowerSummary? {
        let all = segments.flatMap { $0 }
        guard !all.isEmpty else { return nil }
        return PowerSummary(
            duration: TimeInterval(all.count),
            averagePower: all.reduce(0, +) / Double(all.count),
            maxPower: all.max() ?? 0,
            normalizedPower: normalizedPower(segments: segments),
            best20Minutes: bestAverage(segments: segments, seconds: 1200),
            best5Minutes: bestAverage(segments: segments, seconds: 300)
        )
    }

    /// Potencia normalizada: media móvil de 30 s, a la cuarta potencia, media y raíz cuarta.
    public static func normalizedPower(segments: [[Double]]) -> Double? {
        guard TimeInterval(segments.reduce(0) { $0 + $1.count }) >= minimumNormalizedDuration else { return nil }
        var sum = 0.0
        var count = 0
        for segment in segments where segment.count >= normalizedWindow {
            var window = segment.prefix(normalizedWindow).reduce(0, +)
            for index in normalizedWindow...segment.count {
                if index > normalizedWindow {
                    window += segment[index - 1] - segment[index - 1 - normalizedWindow]
                }
                let mean = window / Double(normalizedWindow)
                sum += pow(mean, 4)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return pow(sum / Double(count), 0.25)
    }

    /// Mejor media de `seconds` segundos seguidos dentro de un mismo tramo.
    public static func bestAverage(segments: [[Double]], seconds: Int) -> Double? {
        guard seconds > 0 else { return nil }
        var best: Double?
        for segment in segments where segment.count >= seconds {
            var window = segment.prefix(seconds).reduce(0, +)
            var top = window
            for index in seconds..<segment.count {
                window += segment[index] - segment[index - seconds]
                top = max(top, window)
            }
            best = max(best ?? 0, top / Double(seconds))
        }
        return best
    }

    /// Segundos en cada zona de potencia (índice 0 sin usar, 1…7).
    public static func zoneSeconds(segments: [[Double]], ftp: Double) -> [TimeInterval] {
        var seconds = Array(repeating: TimeInterval(0), count: 8)
        guard ftp > 0 else { return seconds }
        for watts in segments.joined() {
            if let zone = PowerZones.zone(for: watts, ftp: ftp) {
                seconds[zone] += 1
            }
        }
        return seconds
    }
}

/// FTP guardado en Apple Health (p. ej. el que calcula el Apple Watch con un medidor).
public struct ThresholdPowerReading: Hashable, Sendable {
    public let watts: Double
    public let date: Date
    public let origin: DataOrigin

    public init(watts: Double, date: Date, origin: DataOrigin) {
        self.watts = watts
        self.date = date
        self.origin = origin
    }
}

/// FTP estimado a partir de las salidas con potencia: 95 % de la mejor media
/// de 20 minutos de las últimas `windowDays` jornadas (prueba de 20 min de Allen
/// y Coggan). Es una estimación: solo vale si alguno de esos 20 minutos fue un
/// esfuerzo máximo sostenido.
public struct FTPEstimate: Hashable, Sendable {
    public let watts: Double
    public let best20Minutes: Double
    public let rideID: UUID
    public let rideDate: Date

    public static let factor = 0.95
    public static let windowDays = 42
}

public enum FTPEstimator {
    public static func estimate(rides: [(ride: WorkoutSummary, best20Minutes: Double?)], today: Date, calendar: Calendar) -> FTPEstimate? {
        let start = calendar.date(byAdding: .day, value: -FTPEstimate.windowDays, to: calendar.startOfDay(for: today)) ?? today
        let best = rides
            .filter { $0.ride.activity.isRide && $0.ride.start >= start && $0.ride.start <= today }
            .compactMap { item in item.best20Minutes.map { (item.ride, $0) } }
            .max { $0.1 < $1.1 }
        guard let best, best.1 > 0 else { return nil }
        return FTPEstimate(watts: (best.1 * FTPEstimate.factor).rounded(), best20Minutes: best.1, rideID: best.0.id, rideDate: best.0.start)
    }
}
