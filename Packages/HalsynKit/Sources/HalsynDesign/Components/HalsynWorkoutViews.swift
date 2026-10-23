#if canImport(SwiftUI)
import HalsynCore
import SwiftUI

/// Métrica compacta para la interfaz de Apple Watch (fuera de entrenamiento).
public struct HalsynWatchMetric: View {
    private let title: String
    private let systemImage: String
    private let value: String?
    private let unit: String

    public init(title: String, systemImage: String, value: String?, unit: String) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        HStack(spacing: HalsynSpacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(Color(HalsynPalette.darkAccent))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: value ?? "—")
                        .font(.title3.weight(.semibold).monospacedDigit())
                    if value != nil {
                        Text(verbatim: unit).font(.caption2).foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                    }
                }
                Text(LocalizedStringKey(title))
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(HalsynPalette.textLight))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(verbatim: value.map { "\($0) \(unit)" } ?? "Sin datos"))
    }
}

/// Tamaño de un campo de entrenamiento según la distribución elegida.
public enum HalsynWorkoutFieldSize: Sendable {
    case hero
    case large
    case medium
    case small

    var valueFont: Font {
        switch self {
        case .hero: .system(size: 64, weight: .semibold, design: .rounded).monospacedDigit()
        case .large: .system(size: 44, weight: .semibold, design: .rounded).monospacedDigit()
        case .medium: .system(size: 32, weight: .semibold, design: .rounded).monospacedDigit()
        case .small: .system(size: 24, weight: .semibold, design: .rounded).monospacedDigit()
        }
    }
}

/// Campo de una pantalla de entrenamiento: número grande, unidad clara,
/// etiqueta corta. Fondo oscuro y máximo contraste, sin decoración.
public struct HalsynWorkoutField: View {
    private let label: String
    private let value: String?
    private let unit: String
    private let size: HalsynWorkoutFieldSize
    private let emphasis: Color

    public init(label: String, value: String?, unit: String, size: HalsynWorkoutFieldSize = .medium, emphasis: Color = Color(HalsynPalette.darkAccent)) {
        self.label = label
        self.value = value
        self.unit = unit
        self.size = size
        self.emphasis = emphasis
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: label)
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(emphasis)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value ?? "--")
                    .font(size.valueFont)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Color.white)
                if !unit.isEmpty {
                    Text(verbatim: unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: value.map { "\($0) \(unit)" } ?? "Sin datos"))
    }
}

#Preview("Campos de entrenamiento") {
    VStack(alignment: .leading, spacing: 8) {
        HalsynWorkoutField(label: "TID", value: "24:36", unit: "", size: .large)
        HalsynWorkoutField(label: "DISTANCIA", value: "5.21", unit: "km")
        HalsynWorkoutField(label: "RITMO", value: "4:42", unit: "/km")
        HalsynWorkoutField(label: "PULS", value: "148", unit: "lpm", emphasis: Color(HalsynPalette.alertDark))
        HalsynWatchMetric(title: "FC reposo", systemImage: "heart", value: "54", unit: "lpm")
    }
    .padding()
    .background(Color(HalsynPalette.darkBackground))
}
#endif

#if canImport(SwiftUI)
/// Pantalla de entrenamiento según un `WorkoutScreenProfile`. Se usa en el reloj
/// durante la carrera y en la vista previa del editor del iPhone.
public struct HalsynWorkoutScreen: View {
    private let profile: WorkoutScreenProfile
    private let valueFor: (WorkoutFieldKind) -> WorkoutFieldValue

    public init(profile: WorkoutScreenProfile, valueFor: @escaping (WorkoutFieldKind) -> WorkoutFieldValue) {
        self.profile = profile
        self.valueFor = valueFor
    }

    public var body: some View {
        let fields = Array(profile.fields.prefix(profile.layout.fieldCount))
        VStack(alignment: .leading, spacing: 4) {
            if profile.layout == .six {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                    ForEach(fields) { field in
                        fieldView(field, size: .small)
                    }
                }
            } else {
                ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                    fieldView(field, size: size(forIndex: index, count: fields.count))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func size(forIndex index: Int, count: Int) -> HalsynWorkoutFieldSize {
        switch count {
        case 1: .hero
        case 2: .large
        default: index == 0 ? .large : .medium
        }
    }

    private func fieldView(_ field: WorkoutFieldKind, size: HalsynWorkoutFieldSize) -> some View {
        let item = valueFor(field)
        return HalsynWorkoutField(
            label: field.label,
            value: item.value,
            unit: item.unit,
            size: size,
            emphasis: field == .heartRate || field == .heartRateZone ? Color(HalsynPalette.alertDark) : Color(HalsynPalette.darkAccent)
        )
    }
}
#endif
