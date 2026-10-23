import HalsynCore
import HalsynDesign
import SwiftUI
import WidgetKit

// MARK: - Línea de tiempo

struct HalsynWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Lee el último resumen que dejó la app. Se refresca cada 30 min (para el
/// aviso de "datos de hace X") y cada vez que la app pide recargar.
struct HalsynWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HalsynWidgetEntry {
        HalsynWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (HalsynWidgetEntry) -> Void) {
        completion(HalsynWidgetEntry(date: .now, snapshot: context.isPreview ? .placeholder : load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HalsynWidgetEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [HalsynWidgetEntry(date: now, snapshot: load())], policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func load() -> WidgetSnapshot? {
        WidgetSnapshotStore.sharedDefaults().flatMap(WidgetSnapshotStore.load(from:))
    }
}

// MARK: - Piezas

/// Anillo de puntuación compacto (misma geometría que `HalsynScoreRing`).
struct WidgetRing: View {
    let value: Int?
    var lineWidth: CGFloat = 8
    var tint: Color = .halsynAccent

    var body: some View {
        ZStack {
            Circle().inset(by: lineWidth / 2).stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: Double(value ?? 0) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: value.map(String.init) ?? "—")
                .font(.system(size: 30, weight: .light, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
                .padding(lineWidth)
        }
    }
}

/// Valores del día: solo si el resumen es de hoy (si no, "—").
struct WidgetValues {
    let snapshot: WidgetSnapshot?
    let date: Date

    var isToday: Bool { snapshot?.isFromToday(date, calendar: .current) ?? false }
    var score: Int? { isToday ? snapshot?.score : nil }
    var recovery: Int? { isToday ? snapshot?.recovery : nil }
    var steps: String? { isToday ? snapshot?.steps.map { HalsynFormat.integer($0) } : nil }
    var sleep: String? { isToday ? snapshot?.sleepHours.map { sleepText($0 * 3600) } : nil }
    var goal: WidgetSnapshot.GoalSummary? { isToday ? snapshot?.goal : nil }
}

struct WidgetFootnote: View {
    let values: WidgetValues

    var body: some View {
        if values.snapshot == nil {
            Text("Abre HÅLSYN para empezar")
        } else if !values.isToday {
            Text("Abre HÅLSYN para actualizar")
        } else if values.snapshot?.isDemo == true {
            Text("Datos demo")
        } else if let updated = values.snapshot?.updatedAt {
            Text(updated, style: .relative)
        }
    }
}

// MARK: - Widget de estado (HÄLSA + VILA)

struct HalsynStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HalsynWidgetEntry

    private var values: WidgetValues { WidgetValues(snapshot: entry.snapshot, date: entry.date) }

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
            .widgetURL(URL(string: "halsyn://halsa"))
    }

    /// Fondo propio solo en los widgets del iPhone; en pantalla bloqueada y reloj, el del sistema.
    @ViewBuilder
    private var background: some View {
        #if os(iOS)
        if family == .systemSmall || family == .systemMedium {
            Color.halsynSurface
        } else {
            Color.clear
        }
        #else
        Color.clear
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        #if os(iOS)
        case .systemSmall: small
        case .systemMedium: medium
        #endif
        #if os(watchOS)
        case .accessoryCorner:
            Text(verbatim: values.score.map(String.init) ?? "—")
                .font(.title3.monospacedDigit())
                .widgetLabel {
                    Gauge(value: Double(values.score ?? 0), in: 0...100) { Text(verbatim: HalsynModule.halsa.brandName) }
                        .tint(.halsynAccent)
                }
        #endif
        case .accessoryCircular:
            Gauge(value: Double(values.score ?? 0), in: 0...100) {
                Text(verbatim: "H")
            } currentValueLabel: {
                Text(verbatim: values.score.map(String.init) ?? "—")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.halsynAccent)
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text(verbatim: "\(HalsynModule.halsa.brandName) \(values.score.map(String.init) ?? "—") · \(HalsynModule.vila.brandName) \(values.recovery.map(String.init) ?? "—")")
        default:
            rectangular
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: HalsynModule.halsa.brandName)
                    .font(.caption2.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.halsynAccentText)
                Spacer()
                HalsynSymbol().frame(height: 18)
            }
            WidgetRing(value: values.score)
                .foregroundStyle(.halsynPrimaryText)
            WidgetFootnote(values: values)
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
                .lineLimit(1)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                WidgetRing(value: values.score)
                    .foregroundStyle(.halsynPrimaryText)
                Text(verbatim: HalsynModule.halsa.brandName)
                    .font(.caption2.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.halsynAccentText)
            }
            VStack(alignment: .leading, spacing: 8) {
                row("moon", "Recuperación", values.recovery.map(String.init))
                row("shoeprints.fill", "Pasos", values.steps)
                row("bed.double", "Sueño", values.sleep)
                if let goal = values.goal {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: goal.title)
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                            .lineLimit(1)
                        ProgressView(value: goal.fraction)
                            .tint(.halsynAccent)
                    }
                }
                WidgetFootnote(values: values)
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func row(_ systemImage: String, _ title: LocalizedStringKey, _ value: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.halsynAccentText)
                .frame(width: 16)
            Text(title)
                .font(.caption)
                .foregroundStyle(.halsynSecondaryText)
            Spacer(minLength: 4)
            Text(verbatim: value ?? "—")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.halsynPrimaryText)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: HalsynModule.halsa.brandName).font(.caption2.weight(.semibold))
                Text(verbatim: values.score.map(String.init) ?? "—").font(.title3.monospacedDigit())
                Spacer()
                Text(verbatim: HalsynModule.vila.brandName).font(.caption2.weight(.semibold))
                Text(verbatim: values.recovery.map(String.init) ?? "—").font(.title3.monospacedDigit())
            }
            if let goal = values.goal {
                ProgressView(value: goal.fraction) {
                    Text(verbatim: goal.title).font(.caption2).lineLimit(1)
                }
                .tint(.halsynAccent)
            } else {
                WidgetFootnote(values: values).font(.caption2).lineLimit(1)
            }
        }
        .widgetAccentable()
    }
}

struct HalsynStatusWidget: Widget {
    let kind = "HalsynStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalsynWidgetProvider()) { entry in
            HalsynStatusWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(verbatim: HalsynBrand.name))
        .description(Text("Tu puntuación del día y tu recuperación."))
        .supportedFamilies(Self.families)
    }

    #if os(watchOS)
    static let families: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
    #else
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
    #endif
}

// MARK: - Acceso rápido a correr

struct HalsynRunWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HalsynWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                HStack {
                    Image(systemName: "figure.run").font(.title2)
                    VStack(alignment: .leading) {
                        Text(verbatim: HalsynModule.spring.brandName).font(.headline)
                        Text("Empezar a correr").font(.caption2)
                    }
                }
            case .accessoryInline:
                Label {
                    Text(verbatim: HalsynModule.spring.brandName)
                } icon: {
                    Image(systemName: "figure.run")
                }
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "figure.run")
                        .font(.title2.weight(.semibold))
                }
            }
        }
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "halsyn://spring"))
    }
}

struct HalsynRunWidget: Widget {
    let kind = "HalsynRun"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalsynWidgetProvider()) { entry in
            HalsynRunWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(verbatim: HalsynModule.spring.brandName))
        .description(Text("Abre SPRING para empezar a correr."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct HalsynWidgetBundle: WidgetBundle {
    var body: some Widget {
        HalsynStatusWidget()
        HalsynRunWidget()
    }
}
