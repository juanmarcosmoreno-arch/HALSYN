import HalsynDesign
import SwiftUI

/// Texto largo (explicaciones, cómo se calcula) que se muestra en dos líneas
/// y se despliega al tocar «Leer más».
struct ExpandableText: View {
    let text: LocalizedStringKey
    var lines = 2
    @State private var expanded = false

    init(_ text: LocalizedStringKey, lines: Int = 2) {
        self.text = text
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .lineLimit(expanded ? nil : lines)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                Text(expanded ? LocalizedStringKey("Leer menos") : LocalizedStringKey("Leer más"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.halsynAccentText)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Bloque de detalles plegado: un título con flecha y, al tocarlo, el contenido.
struct CollapsibleDetails<Content: View>: View {
    let title: LocalizedStringKey
    var summary: String?
    @ViewBuilder let content: () -> Content
    @State private var expanded = false

    init(_ title: LocalizedStringKey, summary: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.summary = summary
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.halsynPrimaryText)
                        if let summary, !expanded {
                            Text(verbatim: summary)
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.halsynAccentText)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(expanded ? LocalizedStringKey("Toca para ocultar") : LocalizedStringKey("Toca para ver los detalles")))
            if expanded {
                content()
            }
        }
    }
}
