#if canImport(SwiftUI)
import HalsynCore
import SwiftUI

/// Tarjeta base: superficie discreta, esquinas continuas y sombra mínima.
public struct HalsynCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = HalsynSpacing.l, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HalsynRadius.card, style: .continuous)
                    .fill(Color.halsynSurface)
                    .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HalsynRadius.card, style: .continuous)
                    .strokeBorder(Color.halsynHairline, lineWidth: 0.5)
            )
    }
}

/// Cabecera de sección con etiqueta opcional de módulo sueco y acción.
public struct HalsynSectionHeader: View {
    private let title: String
    private let eyebrow: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(_ title: String, eyebrow: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(verbatim: eyebrow).halsynEyebrowStyle()
                }
                Text(LocalizedStringKey(title))
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: HalsynSpacing.s)
            if let actionTitle, let action {
                Button(LocalizedStringKey(actionTitle), action: action)
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynAccentText)
            }
        }
    }
}

/// Distintivo obligatorio cuando se muestran datos sintéticos.
public struct HalsynDemoBadge: View {
    public init() {}

    public var body: some View {
        Label {
            Text("DEMO")
        } icon: {
            Image(systemName: "testtube.2")
        }
        .font(.halsynEyebrow)
        .tracking(1.2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(.halsynCaution)
        .background(Capsule().fill(Color.halsynCaution.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Color.halsynCaution.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Datos de demostración, no son mediciones reales"))
    }
}

/// Estado vacío: explica por qué no hay datos y qué hacer.
public struct HalsynEmptyState: View {
    private let systemImage: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(systemImage: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: HalsynSpacing.s) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.halsynAccent)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
                .font(.halsynHeadline)
                .foregroundStyle(.halsynPrimaryText)
            Text(LocalizedStringKey(message))
                .font(.halsynBody)
                .foregroundStyle(.halsynSecondaryText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                HalsynPrimaryButton(actionTitle, action: action)
                    .padding(.top, HalsynSpacing.xs)
            }
        }
        .padding(HalsynSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Estado de carga discreto.
public struct HalsynLoadingState: View {
    private let message: String

    public init(_ message: String = "Cargando…") {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: HalsynSpacing.s) {
            ProgressView()
                .tint(.halsynAccent)
            Text(LocalizedStringKey(message))
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(HalsynSpacing.xl)
        .accessibilityElement(children: .combine)
    }
}

/// Botón principal de marca.
public struct HalsynPrimaryButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: HalsynSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(LocalizedStringKey(title))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(HalsynPrimaryButtonStyle())
    }
}

public struct HalsynPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.halsynHeadline)
            .foregroundStyle(Color(HalsynPalette.darkBackground))
            .padding(.vertical, HalsynSpacing.m)
            .padding(.horizontal, HalsynSpacing.l)
            .frame(minHeight: 44)
            .background(
                Capsule().fill(HalsynGradients.brand)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
#endif
