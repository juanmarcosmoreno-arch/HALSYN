import Foundation

/// Calcula el ritmo a partir de la distancia acumulada a lo largo del tiempo.
///
/// - **Instantáneo**: último tramo entre dos actualizaciones. Muy ruidoso; solo
///   se expone para depuración.
/// - **Actual (suavizado)**: distancia recorrida en una ventana móvil de
///   `window` segundos (20 s por defecto). Responde a un cambio real de ritmo en
///   unos 10–20 s y no oscila por el ruido punto a punto.
/// - **Medio**: distancia total / tiempo activo (lo calcula `RunSessionTracker`).
///
/// Si no llega distancia nueva en `stallTimeout` segundos (parado), el ritmo
/// actual pasa a `nil` en lugar de mostrar un valor antiguo.
public struct PaceEstimator: Sendable {
    public var window: TimeInterval
    public var minimumSpan: TimeInterval
    public var stallTimeout: TimeInterval

    private var points: [(time: Date, distance: Double)] = []
    /// Último instante en que la distancia avanzó.
    private var lastAdvance: Date?

    public init(window: TimeInterval = 20, minimumSpan: TimeInterval = 5, stallTimeout: TimeInterval = 10) {
        self.window = window
        self.minimumSpan = minimumSpan
        self.stallTimeout = stallTimeout
    }

    public mutating func add(cumulativeDistance distance: Double, at time: Date) {
        if let last = points.last {
            guard time > last.time else { return }
            if distance > last.distance { lastAdvance = time }
        } else {
            lastAdvance = time
        }
        points.append((time, distance))
        let cutoff = time.addingTimeInterval(-window * 2)
        points.removeAll { $0.time < cutoff }
    }

    /// Vacía la ventana (pausa / reanudación), para no mezclar tramos.
    public mutating func reset() {
        points.removeAll()
        lastAdvance = nil
    }

    public func currentPace(at now: Date) -> Pace? {
        guard let last = points.last, let lastAdvance else { return nil }
        // Parado: la distancia no avanza desde hace `stallTimeout`.
        guard now.timeIntervalSince(lastAdvance) <= stallTimeout else { return nil }
        let start = now.addingTimeInterval(-window)
        let inWindow = points.filter { $0.time >= start }
        guard let first = inWindow.first ?? points.first, last.time.timeIntervalSince(first.time) >= minimumSpan else { return nil }
        return Pace(distanceMeters: last.distance - first.distance, duration: last.time.timeIntervalSince(first.time))
    }

    public var instantaneousPace: Pace? {
        guard points.count >= 2 else { return nil }
        let a = points[points.count - 2], b = points[points.count - 1]
        return Pace(distanceMeters: b.distance - a.distance, duration: b.time.timeIntervalSince(a.time))
    }
}
