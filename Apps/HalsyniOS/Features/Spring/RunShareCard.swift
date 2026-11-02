import HalsynCore
import HalsynDesign
import SwiftUI

/// Tarjeta para compartir una carrera (WhatsApp, Instagram…): la forma de la
/// ruta, distancia, tiempo y ritmo, con la marca. Se dibuja sin mapa, así no
/// muestra calles ni dónde vives con detalle.
struct RunShareCard: View {
    let workout: WorkoutSummary
    let route: [LocationSample]
    let unitSystem: UnitSystem

    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(HalsynPalette.darkPrimary), Color(HalsynPalette.darkBackground)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(LocalizedStringKey(workout.activity.title), systemImage: workout.activity.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(HalsynPalette.darkAccent))
                    Spacer()
                    Text(workout.start, format: .dateTime.day().month(.abbreviated).year())
                        .font(.system(size: 12))
                        .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                }
                routeShape
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: workout.distanceMeters.map { HalsynFormat.distance(meters: $0, unit: unitSystem) } ?? "—")
                        .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(verbatim: unitSystem.distanceUnitSymbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                }
                .foregroundStyle(Color.white)
                HStack(spacing: 28) {
                    stat("Tiempo", HalsynFormat.duration(workout.duration), unit: nil)
                    stat("Ritmo medio", workout.averagePace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol)
                    if let heartRate = workout.averageHeartRate {
                        stat("FC media", HalsynFormat.integer(heartRate), unit: "lpm")
                    }
                }
                HStack {
                    HalsynLogo(.compact, height: 18)
                    Spacer()
                    if workout.origin.isDemo {
                        Text("Datos de ejemplo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(HalsynPalette.cautionDark))
                    }
                }
            }
            .padding(24)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var routeShape: some View {
        let points = RouteProjection.normalized(route)
        if points.count > 1 {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let origin = CGPoint(x: (proxy.size.width - side) / 2, y: (proxy.size.height - side) / 2)
                Path { path in
                    for (index, point) in points.enumerated() {
                        let location = CGPoint(x: origin.x + point.x * side, y: origin.y + point.y * side)
                        index == 0 ? path.move(to: location) : path.addLine(to: location)
                    }
                }
                .stroke(Color(HalsynPalette.darkAccent), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .shadow(color: Color(HalsynPalette.darkAccent).opacity(0.5), radius: 6)
            }
        } else {
            Image(systemName: workout.activity.systemImage)
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(Color(HalsynPalette.darkAccent).opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String?, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value ?? "—")
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white)
                if let unit {
                    Text(verbatim: unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                }
            }
        }
    }

    /// Imagen de 1080 × 1350 (4:5, la de Instagram).
    @MainActor
    static func image(workout: WorkoutSummary, route: [LocationSample], unitSystem: UnitSystem) -> Image? {
        let renderer = ImageRenderer(content: RunShareCard(workout: workout, route: route, unitSystem: unitSystem))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}
