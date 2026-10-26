import Foundation

/// Lectura de FC de un entrenamiento.
public struct HeartRatePoint: Hashable, Sendable {
    public let date: Date
    public let bpm: Double

    public init(date: Date, bpm: Double) {
        self.date = date
        self.bpm = bpm
    }
}

/// Datos de detalle de un entrenamiento terminado: ruta, FC y potencia (bici).
/// Vacíos cuando no existen (cinta, sin GPS, sin medidor, sin permiso): no se inventan.
public struct WorkoutDetailData: Hashable, Sendable {
    public var route: [LocationSample]
    public var heartRate: [HeartRatePoint]
    public var power: [PowerSample]
    public var origin: DataOrigin

    public init(route: [LocationSample] = [], heartRate: [HeartRatePoint] = [], power: [PowerSample] = [], origin: DataOrigin) {
        self.route = route
        self.heartRate = heartRate
        self.power = power
        self.origin = origin
    }

    public static func empty(_ origin: DataOrigin) -> WorkoutDetailData {
        WorkoutDetailData(origin: origin)
    }
}

/// Parcial de una carrera (por kilómetro o milla).
public struct Split: Hashable, Identifiable, Sendable {
    public let index: Int
    public let distance: Double
    public let duration: TimeInterval
    /// `false` en el último tramo, más corto que la unidad.
    public let isComplete: Bool

    public var id: Int { index }
    public var pace: Pace? { Pace(distanceMeters: distance, duration: duration) }
    public var speed: Speed? { Speed(distanceMeters: distance, duration: duration) }
}

/// Análisis posterior al entrenamiento a partir de la ruta y la FC guardadas.
public enum WorkoutAnalysis {
    /// Parciales calculados desde la ruta con el mismo filtro GPS que en vivo.
    /// El tiempo solo cuenta entre puntos consecutivos con menos de 30 s de
    /// separación, así las pausas no inflan el parcial. Es una aproximación: la
    /// distancia total guardada por Apple Health puede diferir ligeramente.
    /// - Parameters:
    ///   - splitDistance: largo de cada parcial; por defecto, la unidad (1 km o 1 mi).
    ///   - configuration: filtro GPS (`.cycling` en bici, que admite más velocidad).
    public static func splits(from route: [LocationSample], unit: UnitSystem = .metric, splitDistance: Double? = nil, configuration: GPSDistanceAccumulator.Configuration = .init()) -> [Split] {
        let sorted = route.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count > 1 else { return [] }
        var gps = GPSDistanceAccumulator(configuration: configuration)
        var laps = LapTracker(autoLapDistance: splitDistance ?? unit.metersPerDistanceUnit)
        var elapsed: TimeInterval = 0
        var previous: Date?
        for sample in sorted {
            if let previous {
                let gap = sample.timestamp.timeIntervalSince(previous)
                if gap <= gps.configuration.maxGap {
                    elapsed += max(0, gap)
                }
            }
            previous = sample.timestamp
            gps.add(sample)
            laps.update(distance: gps.distance, elapsed: elapsed)
        }
        var result = laps.laps.map { Split(index: $0.index, distance: $0.distance, duration: $0.duration, isComplete: true) }
        let rest = laps.currentLap(distance: gps.distance, elapsed: elapsed)
        if rest.distance >= Pace.minimumDistanceMeters {
            result.append(Split(index: result.count + 1, distance: rest.distance, duration: rest.duration, isComplete: false))
        }
        return result
    }

    /// Segundos en cada zona (índice 0 = por debajo de Z1). Vacío sin zonas o sin FC.
    public static func zoneSeconds(_ samples: [HeartRatePoint], zones: HeartRateZoneConfiguration) -> [TimeInterval] {
        guard !zones.zones.isEmpty, !samples.isEmpty else { return [] }
        var accumulator = ZoneTimeAccumulator()
        let sorted = samples.sorted { $0.date < $1.date }
        for sample in sorted {
            accumulator.add(zone: zones.zone(for: sample.bpm), at: sample.date)
        }
        if let last = sorted.last {
            // La última lectura cuenta hasta 5 s (intervalo típico del sensor durante un entrenamiento).
            accumulator.breakSegment(at: last.date.addingTimeInterval(5))
        }
        return accumulator.seconds
    }

    /// Reduce una ruta para dibujarla: conserva un punto cada `minimumSpacing` metros.
    public static func simplified(_ route: [LocationSample], minimumSpacing: Double = 10) -> [LocationSample] {
        guard var last = route.first else { return [] }
        var result = [last]
        for sample in route.dropFirst() where sample.distance(to: last) >= minimumSpacing {
            result.append(sample)
            last = sample
        }
        if let final = route.last, final != result.last {
            result.append(final)
        }
        return result
    }
}
