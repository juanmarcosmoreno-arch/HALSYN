import Foundation

extension GPSDistanceAccumulator.Configuration {
    /// En bici: hasta 30 m/s (108 km/h) en bajada; lo demás, igual que corriendo.
    public static var cycling: Self {
        var configuration = Self()
        configuration.maxSpeed = 30
        return configuration
    }
}

/// Punto del perfil de una salida: distancia recorrida, altitud y velocidad.
public struct RideProfilePoint: Hashable, Sendable {
    /// Metros desde la salida.
    public let distance: Double
    /// Altitud GPS en metros (`nil` si el punto no la trae con precisión suficiente).
    public let altitude: Double?
    /// Velocidad de los últimos `RideAnalysis.speedWindow` segundos.
    public let speed: Speed?

    public init(distance: Double, altitude: Double?, speed: Speed?) {
        self.distance = distance
        self.altitude = altitude
        self.speed = speed
    }
}

/// Análisis de una salida en bici a partir de su ruta GPS.
public enum RideAnalysis {
    public static let speedWindow: TimeInterval = 30

    /// Parciales de 5 km (o 5 mi) con el filtro GPS de bici.
    public static func splits(from route: [LocationSample], unit: UnitSystem = .metric) -> [Split] {
        WorkoutAnalysis.splits(from: route, unit: unit, splitDistance: unit.metersPerDistanceUnit * 5, configuration: .cycling)
    }

    /// Desnivel positivo de la ruta (altitud GPS con histéresis). `nil` sin altitudes fiables.
    public static func elevationGain(_ route: [LocationSample]) -> Double? {
        var gps = GPSDistanceAccumulator(configuration: .cycling)
        var hasAltitude = false
        for sample in route.sorted(by: { $0.timestamp < $1.timestamp }) {
            gps.add(sample)
            if let vertical = sample.verticalAccuracy, vertical >= 0, vertical <= gps.configuration.maxVerticalAccuracy, sample.altitude != nil {
                hasAltitude = true
            }
        }
        return hasAltitude ? gps.elevationGain : nil
    }

    /// Perfil de altitud y velocidad a lo largo de la distancia, reducido a
    /// como mucho `maxPoints` puntos (media por tramo).
    public static func profile(from route: [LocationSample], maxPoints: Int = 160) -> [RideProfilePoint] {
        let sorted = route.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count > 1, maxPoints > 0 else { return [] }
        var gps = GPSDistanceAccumulator(configuration: .cycling)
        var trail: [(time: Date, distance: Double)] = []
        var raw: [RideProfilePoint] = []
        for sample in sorted {
            guard gps.add(sample) else { continue }
            trail.append((sample.timestamp, gps.distance))
            trail.removeAll { sample.timestamp.timeIntervalSince($0.time) > speedWindow }
            var speed: Speed?
            if let first = trail.first, sample.timestamp.timeIntervalSince(first.time) >= speedWindow / 2 {
                speed = Speed(distanceMeters: gps.distance - first.distance, duration: sample.timestamp.timeIntervalSince(first.time))
            }
            let altitude = sample.verticalAccuracy.flatMap { $0 >= 0 && $0 <= gps.configuration.maxVerticalAccuracy ? sample.altitude : nil }
            raw.append(RideProfilePoint(distance: gps.distance, altitude: altitude, speed: speed))
        }
        guard let total = raw.last?.distance, total > 0 else { return [] }
        let size = total / Double(maxPoints)
        var buckets: [Int: [RideProfilePoint]] = [:]
        for point in raw {
            buckets[min(Int(point.distance / size), maxPoints - 1), default: []].append(point)
        }
        return buckets.keys.sorted().compactMap { key in
            guard let points = buckets[key], !points.isEmpty else { return nil }
            let altitudes = points.compactMap(\.altitude)
            let speeds = points.compactMap(\.speed?.metersPerSecond)
            return RideProfilePoint(
                distance: points.map(\.distance).reduce(0, +) / Double(points.count),
                altitude: altitudes.isEmpty ? nil : altitudes.reduce(0, +) / Double(altitudes.count),
                speed: speeds.isEmpty ? nil : Speed(metersPerSecond: speeds.reduce(0, +) / Double(speeds.count))
            )
        }
    }
}
