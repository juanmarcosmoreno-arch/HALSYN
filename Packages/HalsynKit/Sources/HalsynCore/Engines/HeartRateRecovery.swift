import Foundation

/// Lectura de FC durante la recuperación: segundos desde que terminó el
/// ejercicio y pulsaciones por minuto.
public struct RecoverySample: Hashable, Codable, Sendable {
    public let elapsed: TimeInterval
    public let bpm: Double

    public init(elapsed: TimeInterval, bpm: Double) {
        self.elapsed = elapsed
        self.bpm = bpm
    }
}

/// Recuperación de la FC tras un entrenamiento: cuánto bajó el pulso al
/// minuto, a los 2 y a los 5 minutos desde la FC con la que se terminó.
public struct HeartRateRecoveryResult: Hashable, Codable, Sendable {
    /// Momento en que terminó el ejercicio (inicio de la recuperación).
    public let date: Date
    /// FC al terminar: la más alta de los últimos segundos de ejercicio.
    public let endHeartRate: Double
    /// Bajada en lpm (positiva = bajó). `nil` si no se llegó a ese minuto.
    public let oneMinute: Double?
    public let twoMinutes: Double?
    public let fiveMinutes: Double?
    /// Curva de la FC durante la recuperación (para el gráfico).
    public let samples: [RecoverySample]

    public init(date: Date, endHeartRate: Double, oneMinute: Double?, twoMinutes: Double?, fiveMinutes: Double?, samples: [RecoverySample]) {
        self.date = date
        self.endHeartRate = endHeartRate
        self.oneMinute = oneMinute
        self.twoMinutes = twoMinutes
        self.fiveMinutes = fiveMinutes
        self.samples = samples
    }
}

public enum HeartRateRecovery {
    /// Segundos de ejercicio al final que se miran para la FC al terminar.
    public static let endWindow: TimeInterval = 20
    /// Distancia máxima a una lectura para dar la FC en un instante.
    public static let tolerance: TimeInterval = 10
    public static let plausibleBPM: ClosedRange<Double> = 30...230

    /// FC al terminar: la más alta de los últimos `endWindow` segundos de
    /// ejercicio (el sensor va con algo de retraso). `nil` sin lecturas.
    public static func endHeartRate(_ readings: [(date: Date, bpm: Double)], end: Date) -> Double? {
        readings
            .filter { $0.date <= end && end.timeIntervalSince($0.date) <= endWindow && plausibleBPM.contains($0.bpm) }
            .map(\.bpm)
            .max()
    }

    /// FC a los `seconds` de recuperación: interpolación entre las lecturas que
    /// lo rodean, o la más cercana si está a menos de `tolerance` segundos.
    public static func heartRate(at seconds: TimeInterval, in samples: [RecoverySample]) -> Double? {
        let sorted = samples.filter { plausibleBPM.contains($0.bpm) }.sorted { $0.elapsed < $1.elapsed }
        guard !sorted.isEmpty else { return nil }
        if let after = sorted.firstIndex(where: { $0.elapsed >= seconds }) {
            let next = sorted[after]
            if after > 0 {
                let previous = sorted[after - 1]
                let span = next.elapsed - previous.elapsed
                if span > 0, seconds - previous.elapsed <= tolerance, next.elapsed - seconds <= tolerance {
                    let fraction = (seconds - previous.elapsed) / span
                    return previous.bpm + (next.bpm - previous.bpm) * fraction
                }
            }
            return next.elapsed - seconds <= tolerance ? next.bpm : nil
        }
        // Después de la última lectura: solo si está muy cerca.
        guard let last = sorted.last, seconds - last.elapsed <= tolerance else { return nil }
        return last.bpm
    }

    /// Resultado con las bajadas a 1, 2 y 5 minutos (las que se alcanzaron).
    public static func result(date: Date, endHeartRate: Double, samples: [RecoverySample]) -> HeartRateRecoveryResult {
        func drop(_ seconds: TimeInterval) -> Double? {
            heartRate(at: seconds, in: samples).map { (endHeartRate - $0).rounded() }
        }
        return HeartRateRecoveryResult(date: date, endHeartRate: endHeartRate, oneMinute: drop(60), twoMinutes: drop(120), fiveMinutes: drop(300), samples: samples)
    }
}

/// Una recuperación para la tendencia: de HÅLSYN (con 2 minutos y FC al terminar)
/// o la «Recuperación cardíaca» de Salud (solo el primer minuto, estimada por Apple).
public struct RecoveryReading: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    /// Bajada en el primer minuto (lpm).
    public let oneMinute: Double
    /// Solo en las de HÅLSYN.
    public let twoMinutes: Double?
    public let endHeartRate: Double?
    public let origin: DataOrigin

    public init(id: UUID = UUID(), date: Date, oneMinute: Double, twoMinutes: Double?, endHeartRate: Double?, origin: DataOrigin) {
        self.id = id
        self.date = date
        self.oneMinute = oneMinute
        self.twoMinutes = twoMinutes
        self.endHeartRate = endHeartRate
        self.origin = origin
    }

    /// Una medición de HÅLSYN como lectura de la tendencia (solo si llegó al minuto).
    public init?(_ result: HeartRateRecoveryResult) {
        guard let oneMinute = result.oneMinute else { return nil }
        self.init(date: result.date, oneMinute: oneMinute, twoMinutes: result.twoMinutes, endHeartRate: result.endHeartRate, origin: .derived(engine: "HÅLSYN"))
    }
}

/// Tendencia: media de las últimas mediciones frente a las anteriores.
public struct RecoveryTrend: Hashable, Sendable {
    public let recentAverage: Double
    public let previousAverage: Double
    public let count: Int

    /// Positivo = ahora baja más (recupera más rápido).
    public var change: Double { recentAverage - previousAverage }

    /// Diferencia mínima para hablar de cambio: el error típico de la bajada al
    /// minuto ronda el 25 por ciento (Buchheit 2014), así que se pide al menos
    /// 3 lpm y un 10 por ciento.
    public var isMeaningful: Bool {
        abs(change) >= max(3, previousAverage * 0.1)
    }

    /// Con `count` mediciones recientes y otras tantas anteriores; `nil` si no hay.
    /// Solo compara mediciones que terminaron con una FC parecida a la última
    /// (±`endHeartRateBand` lpm), porque la recuperación depende de lo fuerte que
    /// se terminó.
    public static let endHeartRateBand: Double = 10

    public static func make(_ readings: [RecoveryReading], count: Int = 5) -> RecoveryTrend? {
        var sorted = readings.sorted { $0.date < $1.date }
        if let reference = sorted.last?.endHeartRate {
            sorted = sorted.filter { reading in
                reading.endHeartRate.map { abs($0 - reference) <= endHeartRateBand } ?? true
            }
        }
        guard count > 0, sorted.count >= count * 2 else { return nil }
        let recent = sorted.suffix(count).map(\.oneMinute)
        let previous = sorted.dropLast(count).suffix(count).map(\.oneMinute)
        return RecoveryTrend(
            recentAverage: recent.reduce(0, +) / Double(recent.count),
            previousAverage: previous.reduce(0, +) / Double(previous.count),
            count: count
        )
    }
}
