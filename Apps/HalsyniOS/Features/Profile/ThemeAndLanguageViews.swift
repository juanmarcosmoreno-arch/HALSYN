import HalsynCore
import HalsynDesign
import SwiftUI
import UIKit

// MARK: - Colores

/// Elegir la combinación de colores de la app (se ve en claro y en oscuro).
struct ThemePickerView: View {
    @AppStorage(HalsynTheme.storageKey) private var themeID = HalsynTheme.halsyn.id

    var body: some View {
        Form {
            Section {
                ForEach(HalsynTheme.all) { theme in
                    Button {
                        themeID = theme.id
                    } label: {
                        HStack(spacing: HalsynSpacing.m) {
                            ThemeSwatch(colors: theme.light)
                            ThemeSwatch(colors: theme.dark)
                            Text(LocalizedStringKey(theme.title))
                                .foregroundStyle(.halsynPrimaryText)
                            Spacer()
                            if theme.id == themeID {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.halsynAccentText)
                            }
                        }
                    }
                    .accessibilityAddTraits(theme.id == themeID ? .isSelected : [])
                }
            } footer: {
                Text("Cada tema tiene su versión clara y oscura (se elige en Apariencia). Los colores de estado, las zonas y el reloj no cambian.")
            }
        }
        .navigationTitle("Colores")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Muestra de un tema: fondo, superficie y acento.
private struct ThemeSwatch: View {
    let colors: HalsynTheme.Colors

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(colors.background))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(colors.surface))
                .padding(5)
            Circle()
                .fill(Color(colors.accent))
                .frame(width: 12, height: 12)
        }
        .frame(width: 34, height: 34)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.halsynHairline))
        .accessibilityHidden(true)
    }
}

// MARK: - Idioma

/// Idioma de la app, independiente del del iPhone. iOS lo aplica al volver a
/// abrir la app (guarda la preferencia en `AppleLanguages` de la app).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, es, en, sv

    var id: String { rawValue }
    static let storageKey = "halsyn.language"

    /// Nombre en su propio idioma, para encontrarlo aunque no entiendas el actual.
    var title: String {
        switch self {
        case .system: String(localized: "Del iPhone")
        case .es: "Español"
        case .en: "English"
        case .sv: "Svenska"
        }
    }

    func apply() {
        let defaults = UserDefaults.standard
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

struct LanguagePicker: View {
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var showsRestart = false

    var body: some View {
        Picker("Idioma", selection: $language) {
            ForEach(AppLanguage.allCases) { option in
                Text(verbatim: option.title).tag(option)
            }
        }
        .onChange(of: language) { _, newValue in
            newValue.apply()
            showsRestart = true
        }
        .alert("Idioma cambiado", isPresented: $showsRestart) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Cierra HÅLSYN (desliza hacia arriba en el selector de apps) y ábrela de nuevo para verla en el idioma nuevo. Los widgets y el reloj siguen el idioma del sistema.")
        }
    }
}
