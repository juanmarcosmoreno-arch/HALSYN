import Foundation

/// Punto de GPS independiente de Core Location (para poder probarlo en Linux).
public struct LocationSample: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    /// Altitud en metros, si el dispositivo la da con precisión aceptable.
    public let altitude: Double?
    /// Radio de incertidumbre horizontal en metros. Negativo = no válido.
    public let horizontalAccuracy: Double
    public let verticalAccuracy: Double?
    public let timestamp: Date

    public init(latitude: Double, longitude: Double, altitude: Double? = nil, horizontalAccuracy: Double, verticalAccuracy: Double? = nil, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.timestamp = timestamp
    }

    /// Distancia sobre la superficie terrestre (haversine), en metros.
    public func distance(to other: LocationSample) -> Double {
        let radius = 6_371_008.8
        let φ1 = latitude * .pi / 180, φ2 = other.latitude * .pi / 180
        let Δφ = (other.latitude - latitude) * .pi / 180
        let Δλ = (other.longitude - longitude) * .pi / 180
        let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * radius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// Acumula distancia y desnivel a partir de puntos GPS filtrando el ruido.
///
/// Reglas (RUNNING_ENGINE.md):
/// 1. Se descartan puntos con precisión horizontal peor que `maxHorizontalAccuracy`.
/// 2. Se descartan saltos imposibles (velocidad > `maxSpeed`).
/// 3. Anti-deriva: la distancia solo avanza cuando el desplazamiento desde el último
///    punto de anclaje supera la precisión declarada (entre 3 y 15 m). Así, estar
///    parado con el GPS "bailando" no suma metros; corriendo, el ancla avanza cada
///    pocos segundos y la suma de tramos rectos apenas recorta las curvas.
/// 4. Tras una pausa o una pérdida larga de señal no se une el hueco con una recta.
/// 5. Desnivel positivo con histéresis de `elevationHysteresis` metros.
public struct GPSDistanceAccumulator: Sendable {
    public struct Configuration: Sendable {
        public var maxHorizontalAccuracy: Double = 25
        /// 12,5 m/s ≈ 1:20 min/km: por encima no es una persona corriendo.
        public var maxSpeed: Double = 12.5
        public var minimumStep: Double = 3
        /// Fracción de la precisión declarada que hay que superar para avanzar.
        public var jitterFactor: Double = 1.0
        /// Tope del umbral, para no recortar curvas cerradas con GPS mediocre.
        public var maximumStep: Double = 15
        /// Sin puntos durante más de esto se considera pérdida de señal.
        public var maxGap: TimeInterval = 30
        public var maxVerticalAccuracy: Double = 10
        public var elevationHysteresis: Double = 3

        public init() {}
    }

    public let configuration: Configuration
    public private(set) var distance: Double = 0
    public private(set) var elevationGain: Double = 0
    public private(set) var acceptedCount = 0
    public private(set) var rejectedCount = 0

    private var anchor: LocationSample?
    private var elevationAnchor: Double?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Añade un punto. Devuelve `true` si es fiable (apto para la ruta).
    @discardableResult
    public mutating func add(_ sample: LocationSample) -> Bool {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= configuration.maxHorizontalAccuracy else {
            rejectedCount += 1
            return false
        }
        defer { updateElevation(with: sample) }

        guard let anchor else {
            self.anchor = sample
            acceptedCount += 1
            return true
        }
        let elapsed = sample.timestamp.timeIntervalSince(anchor.timestamp)
        guard elapsed > 0 else {
            rejectedCount += 1
            return false
        }
        let step = anchor.distance(to: sample)
        if elapsed > configuration.maxGap {
            // Pérdida de señal: se reinicia el ancla sin inventar el tramo.
            self.anchor = sample
            acceptedCount += 1
            return true
        }
        guard step / elapsed <= configuration.maxSpeed else {
            rejectedCount += 1
            return false
        }
        let threshold = min(
            configuration.maximumStep,
            max(configuration.minimumStep, max(sample.horizontalAccuracy, anchor.horizontalAccuracy) * configuration.jitterFactor)
        )
        if step >= threshold {
            distance += step
            self.anchor = sample
        }
        acceptedCount += 1
        return true
    }

    /// Llamar al pausar o reanudar: el siguiente punto empieza un tramo nuevo.
    public mutating func breakSegment() {
        anchor = nil
        elevationAnchor = nil
    }

    private mutating func updateElevation(with sample: LocationSample) {
        guard let altitude = sample.altitude,
              let vertical = sample.verticalAccuracy, vertical >= 0, vertical <= configuration.maxVerticalAccuracy else { return }
        guard let reference = elevationAnchor else {
            elevationAnchor = altitude
            return
        }
        let delta = altitude - reference
        if delta >= configuration.elevationHysteresis {
            elevationGain += delta
            elevationAnchor = altitude
        } else if delta <= -configuration.elevationHysteresis {
            elevationAnchor = altitude
        }
    }
}
