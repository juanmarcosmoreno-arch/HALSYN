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
