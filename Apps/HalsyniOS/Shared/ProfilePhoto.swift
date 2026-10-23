import HalsynDesign
import Observation
import PhotosUI
import SwiftUI
import UIKit

/// Foto de perfil. Se guarda solo en el dispositivo (Application Support),
/// recortada en cuadrado y reducida; no se sube a ningún servidor ni se
/// incluye en los datos de salud.
@MainActor
@Observable
final class ProfilePhotoStore {
    static let shared = ProfilePhotoStore()

    private(set) var image: UIImage?
    @ObservationIgnored private let url: URL

    static let maximumSide: CGFloat = 600

    init(directory: URL? = nil) {
        let base = directory ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        url = base.appendingPathComponent("profile-photo.jpg")
        image = UIImage(contentsOfFile: url.path)
    }

    /// Recorta al centro, reduce y guarda. Devuelve `false` si los datos no son una imagen.
    @discardableResult
    func save(_ data: Data) -> Bool {
        guard let source = UIImage(data: data), let square = Self.squareThumbnail(source, side: Self.maximumSide),
              let jpeg = square.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
            image = square
            return true
        } catch {
            return false
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
        image = nil
    }

    static func squareThumbnail(_ image: UIImage, side: CGFloat) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let crop = min(size.width, size.height)
        let target = min(side, crop)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let scale = target / crop
            let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
            image.draw(in: CGRect(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2, width: drawSize.width, height: drawSize.height))
        }
    }
}

/// Avatar redondo: la foto del usuario, o sus iniciales, o el símbolo de la marca.
struct ProfileAvatar: View {
    var size: CGFloat = 40
    @AppStorage(AppPreferences.userNameKey) private var name = ""
    private var store: ProfilePhotoStore { .shared }

    var body: some View {
        ZStack {
            if let image = store.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let initials {
                Circle().fill(Color.halsynAccentSoft.opacity(0.5))
                Text(verbatim: initials)
                    .font(.system(size: size * 0.4, weight: .medium, design: .rounded))
                    .foregroundStyle(.halsynAccentText)
            } else {
                Circle().fill(Color.halsynAccentSoft.opacity(0.5))
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.halsynAccentText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.halsynHairline, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var initials: String? {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? nil : String(letters).uppercased()
    }
}

/// Sección del Perfil para la foto y el nombre.
struct ProfileIdentitySection: View {
    @AppStorage(AppPreferences.userNameKey) private var name = ""
    @State private var selection: PhotosPickerItem?
    @State private var failed = false
    private var store: ProfilePhotoStore { .shared }

    var body: some View {
        Section {
            HStack(spacing: HalsynSpacing.m) {
                ProfileAvatar(size: 72)
                VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label(store.image == nil ? LocalizedStringKey("Elegir foto") : LocalizedStringKey("Cambiar foto"), systemImage: "photo")
                    }
                    if store.image != nil {
                        Button(role: .destructive) {
                            store.remove()
                        } label: {
                            Label("Quitar foto", systemImage: "trash")
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, HalsynSpacing.xs)
            TextField("Tu nombre", text: $name)
                .textContentType(.givenName)
                .submitLabel(.done)
        } footer: {
            if failed {
                Text("No se pudo usar esa imagen. Prueba con otra.")
            } else {
                Text("La foto y el nombre se guardan solo en este iPhone.")
            }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                failed = !(data.map { store.save($0) } ?? false)
                selection = nil
            }
        }
    }
}
