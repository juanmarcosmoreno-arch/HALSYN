import Foundation

/// Proyecta una ruta GPS a un cuadrado 0…1 (para dibujarla sin mapa, por
/// ejemplo en la tarjeta para compartir). Equirrectangular con la longitud
/// corregida por la latitud: en distancias de una carrera la forma es fiel.
/// Conserva la proporción y la centra; `y` crece hacia abajo (norte arriba).
public enum RouteProjection {
    public struct Point: Hashable, Sendable {
        public let x: Double
        public let y: Double
    }

    /// Como mucho `maximumPoints` puntos (dibujar miles no aporta nada).
    public static func normalized(_ route: [LocationSample], maximumPoints: Int = 400) -> [Point] {
        guard route.count > 1 else { return [] }
        let step = max(1, Int((Double(route.count) / Double(maximumPoints)).rounded(.up)))
        var samples = stride(from: 0, to: route.count, by: step).map { route[$0] }
        if let last = route.last, samples.last != last { samples.append(last) }
        let meanLatitude = samples.map(\.latitude).reduce(0, +) / Double(samples.count)
        let scaleX = cos(meanLatitude * .pi / 180)
        let raw = samples.map { (x: $0.longitude * scaleX, y: -$0.latitude) }
        guard let minX = raw.map(\.x).min(), let maxX = raw.map(\.x).max(),
              let minY = raw.map(\.y).min(), let maxY = raw.map(\.y).max() else { return [] }
        let span = max(maxX - minX, maxY - minY)
        guard span > 0 else { return [] }
        // Centrado en el cuadrado.
        let offsetX = (span - (maxX - minX)) / 2
        let offsetY = (span - (maxY - minY)) / 2
        return raw.map { Point(x: ($0.x - minX + offsetX) / span, y: ($0.y - minY + offsetY) / span) }
    }
}
