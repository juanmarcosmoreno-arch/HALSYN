import Foundation

/// Coordenada de una huella de recorrido.
public struct RouteCoordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Huella de un recorrido: puntos cada 25 m a lo largo de la ruta filtrada.
public struct RouteFingerprint: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    /// Distancia de la ruta filtrada (m).
    public let distance: Double
    public let points: [RouteCoordinate]

    public init(id: UUID, date: Date, distance: Double, points: [RouteCoordinate]) {
        self.id = id
        self.date = date
        self.distance = distance
        self.points = points
    }

    /// Circuito: termina a menos de 150 m de donde empezó.
    public var isLoop: Bool {
        guard let first = points.first, let last = points.last else { return false }
        return RouteMatching.meters(first, last) <= RouteMatching.endpointTolerance
    }
}

/// Qué tan bien coinciden dos recorridos.
public struct RouteMatchQuality: Hashable, Sendable {
    /// Fracción de cada ruta que cae dentro del corredor de la otra (0–1).
    public let coverage: Double
    /// Fracción de pasos que avanzan en el mismo sentido (0–1).
    public let sameDirection: Double

    public var isMatch: Bool { coverage >= RouteMatching.minimumCoverage && sameDirection >= RouteMatching.minimumDirection }
}

/// Un recorrido que repetiste.
public struct RouteGroup: Hashable, Identifiable, Sendable {
    /// La primera carrera del recorrido (su referencia): estable mientras no aparezca una anterior.
    public let id: UUID
    /// Carreras del recorrido, de la más vieja a la más nueva.
    public let members: [UUID]
    public let distance: Double
    public let isLoop: Bool
    /// Coincidencia de cada carrera con la referencia.
    public let quality: [UUID: RouteMatchQuality]
}

/// Recorridos repetidos: reconoce cuándo corres el mismo trayecto.
///
/// - **Huella**: puntos cada 25 m a lo largo de la ruta, con el mismo filtro
///   GPS que en vivo (sin saltos ni puntos imprecisos).
/// - **Filtro previo** (barato): distancias a menos de un 10 % y referencias
///   a menos de 2 km. Solo entonces se comparan las formas.
/// - **Corredor**: dos rutas son la misma si al menos el 85 % de los puntos de
///   **cada una** cae a menos de 30 m de la otra (cuadrícula de 30 m: lineal,
///   no cuadrático). Distancias parecidas por sí solas no alcanzan.
/// - **Sentido**: el mismo recorrido al revés es otro. Cada punto se empareja
///   con el de la otra ruta más cercano a su avance esperado (así funciona en
///   ida y vuelta, donde la ida y la vuelta pasan por el mismo lugar) y al
///   menos el 70 % de los pasos tiene que avanzar.
/// - **Inicio y fin**: a menos de 150 m, salvo en circuitos (pueden empezar en
///   otro punto del mismo circuito).
/// - **Sin encadenar**: una carrera entra en un grupo solo si coincide con la
///   referencia del grupo (su primera carrera), no con cualquiera de sus
///   miembros; así rutas parecidas en cadena no terminan juntando recorridos
///   distintos.
public enum RouteMatching {
    public static let version = "1.0"
    public static let spacing = 25.0
    public static let corridor = 30.0
    public static let minimumCoverage = 0.85
    public static let minimumDirection = 0.7
    public static let maximumDistanceDifference = 0.10
    public static let endpointTolerance = 150.0
    public static let maximumReferenceSeparation = 2000.0
    public static let maximumPoints = 2000

    // MARK: Huella

    public static func fingerprint(id: UUID, date: Date, route: [LocationSample]) -> RouteFingerprint? {
        let sorted = route.sorted { $0.timestamp < $1.timestamp }
        var gps = GPSDistanceAccumulator()
        var accepted: [(sample: LocationSample, distance: Double)] = []
        for sample in sorted where gps.add(sample) {
            if accepted.isEmpty || gps.distance > accepted[accepted.count - 1].distance {
                accepted.append((sample, gps.distance))
            }
        }
        guard let first = accepted.first, let last = accepted.last, last.distance >= 1000 else { return nil }
        var points = [RouteCoordinate(latitude: first.sample.latitude, longitude: first.sample.longitude)]
        var next = spacing
        for index in accepted.indices.dropFirst() {
            let a = accepted[index - 1], b = accepted[index]
            while next <= b.distance && points.count < maximumPoints {
                let span = b.distance - a.distance
                let fraction = span > 0 ? (next - a.distance) / span : 0
                points.append(RouteCoordinate(
                    latitude: a.sample.latitude + (b.sample.latitude - a.sample.latitude) * fraction,
                    longitude: a.sample.longitude + (b.sample.longitude - a.sample.longitude) * fraction
                ))
                next += spacing
            }
        }
        return RouteFingerprint(id: id, date: date, distance: last.distance, points: points)
    }

    // MARK: Geometría

    static func meters(_ a: RouteCoordinate, _ b: RouteCoordinate) -> Double {
        let latitude = (a.latitude + b.latitude) / 2 * .pi / 180
        let dx = (b.longitude - a.longitude) * cos(latitude) * 111_320
        let dy = (b.latitude - a.latitude) * 110_540
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Cuadrícula de 30 m de los puntos de una ruta (para buscar vecinos sin comparar todos con todos).
    private struct Grid {
        let origin: RouteCoordinate
        let cosLatitude: Double
        var cells: [Int64: [Int]] = [:]

        init(_ points: [RouteCoordinate]) {
            origin = points.first ?? RouteCoordinate(latitude: 0, longitude: 0)
            cosLatitude = cos(origin.latitude * .pi / 180)
            for (index, point) in points.enumerated() {
                cells[key(cell(point)), default: []].append(index)
            }
        }

        func cell(_ point: RouteCoordinate) -> (Int, Int) {
            let x = (point.longitude - origin.longitude) * cosLatitude * 111_320
            let y = (point.latitude - origin.latitude) * 110_540
            return (Int((x / RouteMatching.corridor).rounded(.down)), Int((y / RouteMatching.corridor).rounded(.down)))
        }

        func key(_ cell: (Int, Int)) -> Int64 { Int64(cell.0) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: cell.1))) }

        func neighbours(_ point: RouteCoordinate) -> [Int] {
            let (cx, cy) = cell(point)
            var result: [Int] = []
            for dx in -1...1 { for dy in -1...1 { result += cells[key((cx + dx, cy + dy))] ?? [] } }
            return result
        }
    }

    /// Cobertura y sentido de `a` frente a `b`.
    private static func oneWay(_ a: RouteFingerprint, _ b: RouteFingerprint, grid: Grid) -> (coverage: Double, forward: Double) {
        guard a.points.count > 1, b.points.count > 1 else { return (0, 0) }
        let n = b.points.count
        var covered = 0
        var matches: [Int?] = []
        for (index, point) in a.points.enumerated() {
            let candidates = grid.neighbours(point).filter { meters(point, b.points[$0]) <= corridor }
            guard !candidates.isEmpty else {
                matches.append(nil)
                continue
            }
            covered += 1
            // El candidato más cercano al avance esperado (ida y vuelta: distingue ida de vuelta).
            let expected = Double(index) / Double(a.points.count - 1) * Double(n - 1)
            let best = candidates.min { lhs, rhs in
                progressGap(Double(lhs), expected, n: n, loop: b.isLoop) < progressGap(Double(rhs), expected, n: n, loop: b.isLoop)
            }
            matches.append(best)
        }
        // Sentido: pasos consecutivos emparejados que avanzan.
        var steps = 0, forward = 0
        var previous: Int?
        for match in matches {
            guard let match else { continue }
            if let previous, match != previous {
                steps += 1
                var delta = match - previous
                if b.isLoop, abs(delta) > n / 2 { delta += delta > 0 ? -n : n }
                if delta > 0 { forward += 1 }
            }
            previous = match
        }
        return (Double(covered) / Double(a.points.count), steps > 0 ? Double(forward) / Double(steps) : 0)
    }

    private static func progressGap(_ index: Double, _ expected: Double, n: Int, loop: Bool) -> Double {
        let gap = abs(index - expected)
        return loop ? min(gap, Double(n) - gap) : gap
    }

    /// Coincidencia entre dos recorridos (nil si ya el filtro previo los separa).
    public static func match(_ a: RouteFingerprint, _ b: RouteFingerprint) -> RouteMatchQuality? {
        guard let a0 = a.points.first, let b0 = b.points.first, let a1 = a.points.last, let b1 = b.points.last else { return nil }
        let larger = max(a.distance, b.distance)
        guard larger > 0, abs(a.distance - b.distance) / larger <= maximumDistanceDifference else { return nil }
        guard meters(a0, b0) <= maximumReferenceSeparation || (a.isLoop && b.isLoop) else { return nil }
        if !(a.isLoop && b.isLoop) {
            guard meters(a0, b0) <= endpointTolerance, meters(a1, b1) <= endpointTolerance else { return nil }
        }
        let ab = oneWay(a, b, grid: Grid(b.points))
        let ba = oneWay(b, a, grid: Grid(a.points))
        return RouteMatchQuality(coverage: min(ab.coverage, ba.coverage), sameDirection: min(ab.forward, ba.forward))
    }

    // MARK: Grupos

    /// Agrupa los recorridos repetidos (en orden de fecha; cada carrera solo se
    /// compara con la referencia de cada grupo). Devuelve solo los grupos con 2 o más carreras.
    public static func groups(_ fingerprints: [RouteFingerprint]) -> [RouteGroup] {
        var references: [RouteFingerprint] = []
        var members: [UUID: [UUID]] = [:]
        var qualities: [UUID: [UUID: RouteMatchQuality]] = [:]
        for fingerprint in fingerprints.sorted(by: { $0.date < $1.date }) {
            var bestGroup: (index: Int, quality: RouteMatchQuality)?
            for (index, reference) in references.enumerated() {
                guard let quality = match(fingerprint, reference), quality.isMatch else { continue }
                if bestGroup == nil || quality.coverage > bestGroup!.quality.coverage { bestGroup = (index, quality) }
            }
            if let bestGroup {
                let reference = references[bestGroup.index]
                members[reference.id, default: []].append(fingerprint.id)
                qualities[reference.id, default: [:]][fingerprint.id] = bestGroup.quality
            } else {
                references.append(fingerprint)
                members[fingerprint.id] = [fingerprint.id]
                qualities[fingerprint.id] = [fingerprint.id: RouteMatchQuality(coverage: 1, sameDirection: 1)]
            }
        }
        return references.compactMap { reference in
            guard let list = members[reference.id], list.count >= 2 else { return nil }
            return RouteGroup(id: reference.id, members: list, distance: reference.distance, isLoop: reference.isLoop, quality: qualities[reference.id] ?? [:])
        }
    }
}

/// Una carrera de un recorrido frente a las demás del mismo recorrido.
public struct RouteComparison: Hashable, Sendable {
    public let runID: UUID
    /// Puesto por tiempo en movimiento (1 = la más rápida) entre las comparables.
    public let rank: Int?
    public let comparableCount: Int
    /// Tiempo en movimiento frente a la anterior y frente a la mejor (s; negativo = más rápida).
    public let versusPrevious: TimeInterval?
    public let versusBest: TimeInterval?
    /// Pulso medio frente a la anterior (lpm).
    public let heartRateVersusPrevious: Double?
    /// Pausas de más de 1 min: el tiempo total no es comparable.
    public let hasLongPauses: Bool
    public let quality: RouteMatchQuality?
}

public enum RouteComparisonEngine {
    /// Pausas mayores que esto hacen que el tiempo total no sea comparable.
    public static let maximumPause: TimeInterval = 60

    /// Compara `runID` con las carreras **anteriores o iguales** del grupo.
    public static func compare(_ runID: UUID, group: RouteGroup, runs: [UUID: WorkoutSummary]) -> RouteComparison? {
        guard let run = runs[runID], group.members.contains(runID) else { return nil }
        func paused(_ workout: WorkoutSummary) -> Bool { workout.wallClockEnd.timeIntervalSince(workout.start) - workout.duration > maximumPause }
        let members = group.members.compactMap { runs[$0] }.sorted { $0.start < $1.start }
        let comparable = members.filter { !paused($0) }
        let sorted = comparable.map(\.duration).sorted()
        let rank = paused(run) ? nil : sorted.firstIndex(of: run.duration).map { $0 + 1 }
        let previous = members.last { $0.start < run.start }
        let best = comparable.filter { $0.id != run.id }.min { $0.duration < $1.duration }
        return RouteComparison(
            runID: runID,
            rank: rank,
            comparableCount: comparable.count,
            versusPrevious: previous.map { run.duration - $0.duration },
            versusBest: best.map { run.duration - $0.duration },
            heartRateVersusPrevious: {
                guard let now = run.averageHeartRate, let before = previous?.averageHeartRate else { return nil }
                return now - before
            }(),
            hasLongPauses: paused(run),
            quality: group.quality[runID]
        )
    }
}
