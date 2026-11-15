import HalsynCore
import HalsynDesign
import ImageIO
import MapKit
import PhotosUI
import SwiftUI
import UIKit

/// Formato de la imagen para compartir.
enum RunShareFormat: String, CaseIterable, Identifiable {
    /// 9:16 (historias de Instagram, estados de WhatsApp).
    case story
    /// 4:5 (publicación).
    case post

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .story: "Historia"
        case .post: "Publicación"
        }
    }

    /// Tamaño en puntos; la imagen sale ×3 (1080 px de ancho).
    var size: CGSize {
        switch self {
        case .story: CGSize(width: 360, height: 640)
        case .post: CGSize(width: 360, height: 450)
        }
    }

    var mapHeight: CGFloat {
        switch self {
        case .story: 300
        case .post: 190
        }
    }
}

/// Aspecto de la imagen para compartir.
enum RunShareStyle: String, CaseIterable, Identifiable {
    /// Tarjeta oscura con el mapa en un recuadro, los datos y los parciales.
    case classic
    /// El mapa a toda la imagen, con el título arriba y los datos abajo.
    case map
    /// Una foto tuya de fondo, con la ruta y los datos encima.
    case photo

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .classic: "Tarjeta"
        case .map: "Mapa"
        case .photo: "Foto"
        }
    }
}

/// Mapa real con la ruta dibujada encima (MapKit, estilo oscuro y sin puntos
/// de interés), para la tarjeta.
enum RunShareMap {
    /// `fullBleed`: mapa a color (como el de Mapas) con sitio arriba y abajo para las franjas de texto.
    static func image(route: [LocationSample], size: CGSize, scale: CGFloat = 3, fullBleed: Bool = false) async -> UIImage? {
        let step = max(1, route.count / 600)
        let coordinates = stride(from: 0, to: route.count, by: step).map { CLLocationCoordinate2D(latitude: route[$0].latitude, longitude: route[$0].longitude) }
            + (route.last.map { [CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)] } ?? [])
        guard coordinates.count > 1 else { return nil }
        var rect = MKMapRect.null
        for coordinate in coordinates {
            rect = rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        let margin = max(rect.width, rect.height) * 0.18 + 150
        let options = MKMapSnapshotter.Options()
        var region = rect.insetBy(dx: -margin, dy: -margin)
        if fullBleed, size.width > 0, size.height > 0 {
            // La ruta queda en la franja central: el alto del mapa crece lo que tapan el título y los datos.
            let visible = max(0.3, 1 - (RunShareCard.topBand + RunShareCard.bottomBand) / size.height)
            let aspect = size.height / size.width
            let width = max(region.width, region.height / (aspect * visible))
            let height = width * aspect
            let shift = (RunShareCard.bottomBand - RunShareCard.topBand) / size.height * height / 2
            region = MKMapRect(x: region.midX - width / 2, y: region.midY - height / 2 + shift, width: width, height: height)
        }
        options.mapRect = region
        options.size = size
        options.scale = scale
        options.traitCollection = UITraitCollection(userInterfaceStyle: fullBleed ? .light : .dark)
        options.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: fullBleed ? .default : .muted)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext
            let points = coordinates.map { snapshot.point(for: $0) }
            let path = UIBezierPath()
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            if fullBleed {
                // Sobre el mapa claro: borde oscuro y línea de la marca, para que se lea bien.
                UIColor(Color(HalsynPalette.deepGreen)).setStroke()
                path.lineWidth = 7.5
                path.stroke()
                UIColor(Color(HalsynPalette.turquoise)).setStroke()
                path.lineWidth = 4.5
                path.stroke()
            } else {
                // Halo y línea de la marca.
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 8, color: UIColor(Color(HalsynPalette.darkAccent)).withAlphaComponent(0.7).cgColor)
                UIColor(Color(HalsynPalette.darkAccent)).setStroke()
                path.lineWidth = 4.5
                path.stroke()
                cg.restoreGState()
            }
            dot(at: points[0], color: UIColor(Color(HalsynPalette.positiveDark)))
            if let last = points.last { dot(at: last, color: UIColor(Color(HalsynPalette.coral))) }
        }
    }

    private static func dot(at point: CGPoint, color: UIColor) {
        let outer = UIBezierPath(ovalIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
        UIColor.white.setFill()
        outer.fill()
        let inner = UIBezierPath(ovalIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
        color.setFill()
        inner.fill()
    }
}

/// Tarjeta para compartir una carrera: mapa con la ruta, distancia, tiempo,
/// ritmo, pulso, desnivel y parciales, con la marca.
struct RunShareCard: View {
    let workout: WorkoutSummary
    let route: [LocationSample]
    let splits: [Split]
    let mapImage: UIImage?
    let format: RunShareFormat
    let unitSystem: UnitSystem
    var style: RunShareStyle = .classic
    var photo: UIImage? = nil

    /// Alto de las franjas de título y de datos en los estilos a toda imagen.
    static let topBand: CGFloat = 76
    static let bottomBand: CGFloat = 150

    private let accent = Color(HalsynPalette.darkAccent)
    private let secondary = Color(HalsynPalette.secondaryTextDark)

    var body: some View {
        if style == .classic {
            classicCard
        } else {
            fullBleedCard
        }
    }

    /// Mapa o foto a toda la imagen: título arriba y datos abajo, sobre franjas oscuras.
    private var fullBleedCard: some View {
        ZStack {
            Color(HalsynPalette.darkBackground)
            if style == .photo, let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: format.size.width, height: format.size.height)
                    .clipped()
            } else if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: format.size.width, height: format.size.height)
                    .clipped()
            }
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .frame(height: Self.topBand)
                    .background(
                        LinearGradient(colors: [Color.black.opacity(0.8), Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    )
                Spacer(minLength: 0)
                if style == .photo {
                    // Sobre la foto, la forma de la ruta (sin mapa).
                    HStack {
                        Spacer()
                        routeShape
                            .frame(width: 110, height: 110)
                            .shadow(color: .black.opacity(0.6), radius: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        bandValue(workout.distanceMeters.map { HalsynFormat.distance(meters: $0, unit: unitSystem) } ?? "—", unit: unitSystem.distanceUnitSymbol, label: "Distancia", large: true)
                        bandValue(HalsynFormat.duration(workout.duration), unit: nil, label: "Tiempo", large: true)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        if let pace = workout.averagePace {
                            bandValue(pace.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol, label: "Ritmo", large: false)
                        }
                        if let heartRate = workout.averageHeartRate {
                            bandValue(HalsynFormat.integer(heartRate), unit: "lpm", label: "FC media", large: false)
                        }
                        if let gain = workout.elevationGain, gain >= 1 {
                            bandValue(HalsynFormat.integer(gain), unit: "m", label: "Desnivel", large: false)
                        }
                        Spacer(minLength: 0)
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(height: Self.bottomBand)
                .background(
                    LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .frame(width: format.size.width, height: format.size.height)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    private func bandValue(_ value: String, unit: String?, label: String, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.system(size: large ? 34 : 18, weight: large ? .bold : .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(verbatim: unit)
                        .font(.system(size: large ? 14 : 10, weight: .semibold))
                        .foregroundStyle(large ? accent : secondary)
                }
            }
            Text(LocalizedStringKey(label))
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(secondary)
        }
    }

    private var classicCard: some View {
        ZStack {
            LinearGradient(colors: [Color(HalsynPalette.darkPrimary), Color(HalsynPalette.darkBackground)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: format == .story ? 16 : 12) {
                header
                map
                distance
                stats
                if format == .story, splits.count > 1 {
                    splitBars
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(20)
        }
        .frame(width: format.size.width, height: format.size.height)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(workout.activity.title))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(workout.start, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(secondary)
            }
            Spacer()
            HalsynSymbol().frame(height: 26)
        }
    }

    @ViewBuilder
    private var map: some View {
        Group {
            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFill()
            } else {
                routeShape
                    .padding(20)
                    .background(Color.white.opacity(0.04))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: format.mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    /// Sin mapa (cinta o mapa desactivado): la forma de la ruta, o el icono.
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
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .shadow(color: accent.opacity(0.6), radius: 6)
            }
        } else {
            Image(systemName: workout.activity.systemImage)
                .font(.system(size: 70, weight: .light))
                .foregroundStyle(accent.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var distance: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: workout.distanceMeters.map { HalsynFormat.distance(meters: $0, unit: unitSystem) } ?? "—")
                .font(.system(size: format == .story ? 72 : 58, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(verbatim: unitSystem.distanceUnitSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent)
        }
    }

    private var stats: some View {
        let items = statItems
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
            ForEach(items, id: \.title) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(item.title))
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(verbatim: item.value)
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.white)
                        if let unit = item.unit {
                            Text(verbatim: unit)
                                .font(.system(size: 10))
                                .foregroundStyle(secondary)
                        }
                    }
                }
            }
        }
    }

    private struct StatItem {
        let title: String
        let value: String
        let unit: String?
    }

    private var statItems: [StatItem] {
        var items = [StatItem(title: "Tiempo", value: HalsynFormat.duration(workout.duration), unit: nil)]
        if let pace = workout.averagePace {
            items.append(StatItem(title: "Ritmo", value: pace.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol))
        }
        if let heartRate = workout.averageHeartRate {
            items.append(StatItem(title: "FC media", value: HalsynFormat.integer(heartRate), unit: "lpm"))
        }
        if let gain = workout.elevationGain, gain >= 1 {
            items.append(StatItem(title: "Desnivel", value: HalsynFormat.integer(gain), unit: "m"))
        }
        if let energy = workout.activeEnergyKilocalories {
            items.append(StatItem(title: "Energía", value: HalsynFormat.integer(energy), unit: "kcal"))
        }
        if let fastest = splits.filter(\.isComplete).compactMap(\.pace).min(by: { $0.secondsPerKilometer < $1.secondsPerKilometer }) {
            items.append(StatItem(title: "Mejor parcial", value: fastest.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol))
        }
        return Array(items.prefix(6))
    }

    /// Ritmo de cada parcial: barras más altas = más rápido.
    private var splitBars: some View {
        let complete = splits.filter(\.isComplete).prefix(30)
        let paces = complete.compactMap { $0.pace?.secondsPerKilometer }
        let slowest = paces.max() ?? 1
        let fastest = paces.min() ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Parciales")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(secondary)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(complete), id: \.index) { split in
                    let pace = split.pace?.secondsPerKilometer ?? slowest
                    let share = slowest > fastest ? (slowest - pace) / (slowest - fastest) : 1
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent.opacity(0.45 + 0.55 * share))
                        .frame(height: 14 + 34 * share)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 50, alignment: .bottom)
        }
    }

    private var footer: some View {
        HStack {
            HalsynLogo(.compact, height: 18)
            Spacer()
            if workout.origin.isDemo {
                Text("Datos de ejemplo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(HalsynPalette.cautionDark))
            } else {
                Text(verbatim: HalsynBrand.tagline)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(secondary)
            }
        }
    }
}

/// Pantalla para elegir formato y mapa, ver la tarjeta y compartirla como
/// archivo JPG (WhatsApp, Instagram, Fotos, Mail…).
struct RunShareView: View {
    let workout: WorkoutSummary
    let route: [LocationSample]
    let unitSystem: UnitSystem
    @Environment(\.dismiss) private var dismiss
    @AppStorage("halsyn.share.format") private var format: RunShareFormat = .story
    @AppStorage("halsyn.share.showsMap") private var showsMap = true
    @AppStorage("halsyn.share.style") private var style: RunShareStyle = .classic
    @State private var photo: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var photoFailed = false
    @State private var mapImage: UIImage?
    @State private var rendered: UIImage?
    @State private var file: URL?
    @State private var loadingMap = false

    @State private var photoVersion = 0

    private var splits: [Split] { WorkoutAnalysis.splits(from: route, unit: unitSystem) }

    /// El estilo «Mapa» necesita ruta (no hay en cinta).
    private var availableStyles: [RunShareStyle] {
        route.count > 1 ? RunShareStyle.allCases : [.classic, .photo]
    }

    /// La foto reducida (lado mayor de 2200 px): sin esto una foto de 48 MP agota la memoria.
    private static func downsampled(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 2200,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: HalsynSpacing.m) {
                if let rendered {
                    Image(uiImage: rendered)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                        .frame(maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }
                Picker("Estilo", selection: $style) {
                    ForEach(availableStyles) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Formato", selection: $format) {
                    ForEach(RunShareFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if style == .photo {
                    Button {
                        showsPhotoPicker = true
                    } label: {
                        Label(photo == nil ? LocalizedStringKey("Elegir foto") : LocalizedStringKey("Cambiar foto"), systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    if photoFailed {
                        Text("No se pudo leer esa foto. Prueba con otra.")
                            .font(.caption)
                            .foregroundStyle(.halsynCaution)
                    }
                }
                if route.count > 1, style == .classic {
                    Toggle(isOn: $showsMap) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Mostrar el mapa")
                            Text("Se ve por dónde corriste. Sin mapa, solo la forma de la ruta.")
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                }
                if let file {
                    ShareLink(item: file, preview: SharePreview(Text(LocalizedStringKey(workout.activity.title)), image: Image(uiImage: rendered ?? UIImage()))) {
                        Label("Compartir", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.halsynAccent)
                } else {
                    ProgressView()
                }
            }
            .padding(HalsynSpacing.l)
            .halsynScreenBackground()
            .navigationTitle("Compartir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task(id: "\(format.rawValue)|\(showsMap)|\(style.rawValue)|\(photoVersion)") { await render() }
            .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItem, matching: .images, preferredItemEncoding: .current)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    photoFailed = false
                    if let data = try? await item.loadTransferable(type: Data.self), let image = Self.downsampled(data) {
                        photo = image
                        photoVersion += 1
                    } else {
                        photoFailed = true
                    }
                    photoItem = nil
                }
            }
            .onAppear {
                if !availableStyles.contains(style) { style = .classic }
            }
        }
    }

    private func render() async {
        file = nil
        if style == .map, route.count > 1 {
            mapImage = await RunShareMap.image(route: route, size: format.size, fullBleed: true)
        } else if style == .classic, showsMap, route.count > 1 {
            let size = CGSize(width: format.size.width - 40, height: format.mapHeight)
            mapImage = await RunShareMap.image(route: route, size: size)
        } else {
            mapImage = nil
        }
        if Task.isCancelled { return }
        let card = RunShareCard(workout: workout, route: route, splits: splits, mapImage: mapImage, format: format, unitSystem: unitSystem, style: style, photo: photo)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        rendered = image
        // Como archivo JPG: lo aceptan todas las apps (una imagen suelta no siempre).
        let name = String(format: "HALSYN-%d.jpg", Int(workout.start.timeIntervalSince1970))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if let data = image.jpegData(compressionQuality: 0.9), (try? data.write(to: url, options: .atomic)) != nil {
            file = url
        }
    }
}
