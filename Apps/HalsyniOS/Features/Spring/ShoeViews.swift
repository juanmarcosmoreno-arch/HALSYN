import CoreImage
import HalsynCore
import HalsynDesign
import Observation
import PhotosUI
import SwiftUI
import UIKit
import Vision

/// Zapatillas y sus fotos (recortadas, en este iPhone).
@MainActor
@Observable
final class ShoeStore {
    static let shared = ShoeStore()

    private(set) var closet: ShoeCloset
    /// Fotos ya cargadas, por id.
    private(set) var photos: [UUID: UIImage] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let directory: URL

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("shoes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        closet = ShoeStorage.load(from: defaults)
        for shoe in closet.shoes {
            photos[shoe.id] = UIImage(contentsOfFile: photoURL(shoe.id).path)
        }
    }

    private func photoURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("png") }

    private func persist() { ShoeStorage.save(closet, to: defaults) }

    func save(_ shoe: Shoe) {
        closet.upsert(shoe)
        persist()
    }

    func delete(_ shoe: Shoe) {
        closet.remove(shoe.id)
        try? FileManager.default.removeItem(at: photoURL(shoe.id))
        photos[shoe.id] = nil
        persist()
    }

    func makeDefault(_ shoe: Shoe) {
        closet.defaultShoeID = shoe.id
        persist()
    }

    func assign(_ workout: WorkoutSummary, to shoe: Shoe?) {
        closet.assign(workout.id, to: shoe?.id)
        persist()
    }

    func setPhoto(_ image: UIImage, for id: UUID) {
        guard let png = image.pngData() else { return }
        try? png.write(to: photoURL(id), options: [.atomic, .completeFileProtection])
        photos[id] = image
    }
}

/// Saca la zapatilla del fondo (el mismo recorte de objetos que Fotos, iOS 17)
/// y la deja centrada en un lienzo transparente. Si no encuentra un objeto,
/// devuelve la foto recortada en cuadrado.
enum ShoePhotoProcessor {
    static let side: CGFloat = 900

    @MainActor
    static func process(_ data: Data) async -> UIImage? {
        guard let source = UIImage(data: data)?.normalizedOrientation() else { return nil }
        let lifted = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            liftSubject(source)
        }.value
        return lifted.flatMap { fit($0, padding: 0.06) } ?? ProfilePhotoStore.squareThumbnail(source, side: side)
    }

    private static func liftSubject(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return UIImage(cgImage: output)
        } catch {
            return nil
        }
    }

    /// Centra el objeto en un cuadrado transparente con un margen.
    private static func fit(_ image: UIImage, padding: CGFloat) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let inner = side * (1 - 2 * padding)
        let scale = min(inner / size.width, inner / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2, width: drawSize.width, height: drawSize.height))
        }
    }
}

private extension UIImage {
    /// Las fotos de la cámara vienen giradas por metadatos; Vision necesita los píxeles derechos.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}

// MARK: - Piezas

/// Foto de la zapatilla sobre un fondo suave de la marca (o un icono si no hay foto).
struct ShoeImage: View {
    let shoe: Shoe
    var size: CGFloat = 72
    private var store: ShoeStore { .shared }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Color.halsynAccentSoft.opacity(0.55), Color.halsynAccentSoft.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let photo = store.photos[shoe.id] {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.06)
                    .shadow(color: .black.opacity(0.18), radius: size * 0.05, y: size * 0.04)
            } else {
                Image(systemName: "shoe.2")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(.halsynAccentText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Barra de desgaste: turquesa hasta el 75 %, naranja después, coral al pasar del límite.
struct ShoeWearBar: View {
    let wear: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.halsynHairline)
                Capsule()
                    .fill(color)
                    .frame(width: max(6, proxy.size.width * min(wear, 1)))
            }
        }
        .frame(height: 8)
    }

    private var color: Color {
        switch wear {
        case ..<0.75: .halsynAccent
        case ..<1: .halsynHighlight
        default: Color(HalsynPalette.coral)
        }
    }
}

// MARK: - Tarjeta de SPRING

struct ShoesCard: View {
    let workouts: [WorkoutSummary]
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    private var store: ShoeStore { .shared }

    var body: some View {
        NavigationLink {
            ShoesView(workouts: workouts)
        } label: {
            HalsynCard {
                HStack(spacing: HalsynSpacing.m) {
                    if let shoe = currentShoe {
                        ShoeImage(shoe: shoe, size: 76)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Zapatillas").halsynEyebrowStyle()
                            Text(verbatim: shoe.name)
                                .font(.halsynHeadline)
                                .foregroundStyle(.halsynPrimaryText)
                            Text(verbatim: SessionText.distance(store.closet.distance(of: shoe, workouts: workouts), unit: unitSystem))
                                .font(.halsynCaption.monospacedDigit())
                                .foregroundStyle(.halsynSecondaryText)
                            ShoeWearBar(wear: store.closet.wear(of: shoe, workouts: workouts))
                        }
                    } else {
                        Image(systemName: "shoe.2")
                            .font(.title2)
                            .foregroundStyle(.halsynAccentText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zapatillas").font(.halsynHeadline).foregroundStyle(.halsynPrimaryText)
                            Text("Añade tus zapatillas con una foto y HÅLSYN suma sus kilómetros.")
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var currentShoe: Shoe? {
        let closet = store.closet
        return closet.defaultShoeID.flatMap { id in closet.shoes.first { $0.id == id } } ?? closet.activeShoes.first
    }
}

// MARK: - Lista

struct ShoesView: View {
    let workouts: [WorkoutSummary]
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var editing: Shoe?
    @State private var showsRetired = false
    private var store: ShoeStore { .shared }

    var body: some View {
        HalsynScreen {
            ForEach(store.closet.activeShoes) { shoe in
                shoeCard(shoe)
            }
            HalsynPrimaryButton("Añadir zapatillas", systemImage: "plus") {
                editing = Shoe(name: "", startDate: .now)
            }
            let retired = store.closet.shoes.filter(\.isRetired)
            let retiredCount = retired.count
            if !retired.isEmpty {
                DisclosureGroup(isExpanded: $showsRetired) {
                    ForEach(retired) { shoeCard($0) }
                } label: {
                    Text("Retiradas (\(retiredCount))").font(.halsynHeadline)
                }
            }
            Text("Las carreras se asignan solas a tus zapatillas predeterminadas desde la fecha en que las añades. Puedes cambiarlas en el detalle de cada carrera. Las caminatas no suman.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
        .navigationTitle("Zapatillas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { shoe in
            ShoeEditorView(shoe: shoe)
        }
    }

    private func shoeCard(_ shoe: Shoe) -> some View {
        let closet = store.closet
        let distance = closet.distance(of: shoe, workouts: workouts)
        let wear = closet.wear(of: shoe, workouts: workouts)
        let isDefault = closet.defaultShoeID == shoe.id
        let runCount = closet.runs(of: shoe, workouts: workouts)
        return Button {
            editing = shoe
        } label: {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                    HStack(alignment: .center, spacing: HalsynSpacing.m) {
                        ShoeImage(shoe: shoe, size: 110)
                        VStack(alignment: .leading, spacing: 4) {
                            if isDefault && !shoe.isRetired {
                                Label("Predeterminadas", systemImage: "star.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.halsynAccentText)
                            }
                            Text(verbatim: shoe.name)
                                .font(.halsynTitle)
                                .foregroundStyle(.halsynPrimaryText)
                            Text(verbatim: SessionText.distance(distance, unit: unitSystem))
                                .font(.halsynMetricValue)
                                .foregroundStyle(.halsynPrimaryText)
                            Text("\(runCount) carreras")
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                    ShoeWearBar(wear: wear)
                    if wear >= 1 {
                        Label("Pasaron el límite que elegiste: revisa la amortiguación y la suela.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.halsynCaution)
                    } else {
                        Text("Te avisamos a los \(SessionText.distance(shoe.retirementDistance, unit: unitSystem))")
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isDefault && !shoe.isRetired {
                Button("Usar como predeterminadas", systemImage: "star") { store.makeDefault(shoe) }
            }
        }
    }
}

// MARK: - Editor

struct ShoeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var draft: Shoe
    @State private var selection: PhotosPickerItem?
    @State private var processing = false
    @State private var processed: UIImage?
    @State private var confirmingDelete = false
    private var store: ShoeStore { .shared }
    private let isNew: Bool

    init(shoe: Shoe) {
        _draft = State(initialValue: shoe)
        isNew = !ShoeStore.shared.closet.shoes.contains { $0.id == shoe.id }
    }

    private var unitFactor: Double { unitSystem.metersPerDistanceUnit }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ZStack {
                            if let processed {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                                        .fill(Color.halsynAccentSoft.opacity(0.4))
                                    Image(uiImage: processed).resizable().scaledToFit().padding(10)
                                        .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
                                }
                                .frame(width: 180, height: 180)
                            } else {
                                ShoeImage(shoe: draft, size: 180)
                            }
                            if processing {
                                ProgressView().controlSize(.large)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label(processed == nil && store.photos[draft.id] == nil ? LocalizedStringKey("Elegir foto") : LocalizedStringKey("Cambiar foto"), systemImage: "camera")
                    }
                } footer: {
                    Text("El iPhone recorta la zapatilla y quita el fondo. Funciona mejor con una foto de lado, bien iluminada y sobre un fondo liso.")
                }

                Section {
                    TextField("Nombre (p. ej. Pegasus 41)", text: $draft.name)
                    DatePicker("En uso desde", selection: $draft.startDate, displayedComponents: .date)
                    Stepper(value: Binding(get: { draft.initialDistance / unitFactor }, set: { draft.initialDistance = $0 * unitFactor }), in: 0...2000, step: 10) {
                        LabeledContent("Ya tenían", value: SessionText.distance(draft.initialDistance, unit: unitSystem))
                    }
                    Stepper(value: Binding(get: { draft.retirementDistance / unitFactor }, set: { draft.retirementDistance = $0 * unitFactor }), in: 200...1500, step: 50) {
                        LabeledContent("Avisar a los", value: SessionText.distance(draft.retirementDistance, unit: unitSystem))
                    }
                } footer: {
                    Text("La mayoría de las zapatillas de correr pierden amortiguación entre 500 y 800 km, según el peso, la pisada y el terreno.")
                }

                if !isNew {
                    Section {
                        Toggle("Retiradas", isOn: $draft.isRetired)
                        Button("Borrar zapatillas", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Nuevas zapatillas" : "Zapatillas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        store.save(draft)
                        if let processed { store.setPhoto(processed, for: draft.id) }
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || processing)
                }
            }
            .confirmationDialog("¿Borrar estas zapatillas?", isPresented: $confirmingDelete) {
                Button("Borrar", role: .destructive) {
                    store.delete(draft)
                    dismiss()
                }
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task {
                    processing = true
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        processed = await ShoePhotoProcessor.process(data)
                    }
                    processing = false
                    selection = nil
                }
            }
        }
    }
}

/// Elegir con qué zapatillas se hizo una carrera (en su detalle).
struct WorkoutShoePicker: View {
    let workout: WorkoutSummary
    private var store: ShoeStore { .shared }

    var body: some View {
        let closet = store.closet
        if workout.activity.isRun && !closet.shoes.isEmpty {
            HalsynCard {
                HStack(spacing: HalsynSpacing.m) {
                    if let shoe = closet.shoe(for: workout) {
                        ShoeImage(shoe: shoe, size: 52)
                    } else {
                        Image(systemName: "shoe.2").foregroundStyle(.halsynSecondaryText).frame(width: 52)
                    }
                    Menu {
                        ForEach(closet.shoes.filter { !$0.isRetired || closet.shoe(for: workout)?.id == $0.id }) { shoe in
                            Button(shoe.name) { store.assign(workout, to: shoe) }
                        }
                        Button("Ninguna", role: .destructive) { store.assign(workout, to: nil) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zapatillas").font(.halsynCaption).foregroundStyle(.halsynSecondaryText)
                            HStack {
                                Text(verbatim: closet.shoe(for: workout)?.name ?? String(localized: "Ninguna"))
                                    .font(.halsynHeadline)
                                    .foregroundStyle(.halsynPrimaryText)
                                Image(systemName: "chevron.up.chevron.down").font(.caption)
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}
