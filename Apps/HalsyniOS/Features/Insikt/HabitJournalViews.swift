import HalsynCore
import HalsynDesign
import Observation
import SwiftUI
import UIKit

/// Diario de hábitos: se guarda solo en este iPhone.
@MainActor
@Observable
final class JournalStore {
    static let shared = JournalStore()

    private(set) var journal: HabitJournal
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        journal = HabitJournalStorage.load(from: defaults)
    }

    func tags(on day: Date) -> Set<HabitTag>? {
        journal.tags(on: day, calendar: .current)
    }

    func set(_ tags: Set<HabitTag>, on day: Date) {
        journal.set(tags, on: day, calendar: .current)
        HabitJournalStorage.save(journal, to: defaults)
    }

    func toggle(_ tag: HabitTag, on day: Date) {
        var tags = self.tags(on: day) ?? []
        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
        set(tags, on: day)
    }

    func clear(_ day: Date) {
        journal.remove(day, calendar: .current)
        HabitJournalStorage.save(journal, to: defaults)
    }

    var streak: Int { journal.streak(endingOn: .now, calendar: .current) }

    /// En demo y sin diario propio, uno de ejemplo para ver cómo funciona.
    func journalForAnalysis(isDemo: Bool) -> (journal: HabitJournal, isExample: Bool) {
        if isDemo && journal.entries.isEmpty {
            return (DemoHabitJournal.make(endingOn: .now, calendar: .current), true)
        }
        return (journal, false)
    }
}

// MARK: - Chips

struct HabitChips: View {
    let day: Date
    private var store: JournalStore { .shared }

    var body: some View {
        let selected = store.tags(on: day) ?? []
        FlowLayout(spacing: 8) {
            ForEach(HabitTag.allCases) { tag in
                let isOn = selected.contains(tag)
                Button {
                    store.toggle(tag, on: day)
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Label(LocalizedStringKey(tag.title), systemImage: tag.systemImage)
                        .font(.halsynCaption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .foregroundStyle(isOn ? Color.halsynSurface : Color.halsynPrimaryText)
                        .background(Capsule().fill(isOn ? Color.halsynAccentText : Color.halsynHairline.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Distribuye vistas en filas que se parten al llegar al borde.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Tarjeta de HÄLSA

/// Registro rápido del día: un toque por etiqueta.
struct JournalQuickCard: View {
    private var store: JournalStore { .shared }

    var body: some View {
        let today = Date.now
        let logged = store.tags(on: today) != nil
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack {
                    HalsynSectionHeader("Diario de hoy", eyebrow: HalsynLexicon.tid.rawValue)
                    Spacer()
                    if logged {
                        Label("Registrado", systemImage: "checkmark.circle.fill")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynPositive)
                    }
                }
                Text("Marca lo que hubo hoy. Con unas semanas, INSIKT te muestra cómo influye en tu sueño, tu HRV y tu pulso en reposo.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HabitChips(day: today)
                HStack {
                    if !logged {
                        Button {
                            store.set([], on: today)
                        } label: {
                            Label("Nada de esto hoy", systemImage: "checkmark")
                                .font(.halsynCaption)
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                    if store.streak > 1 {
                        Text("\(store.streak) días seguidos")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    NavigationLink {
                        JournalHistoryView()
                    } label: {
                        Text("Días anteriores")
                            .font(.halsynCaption)
                    }
                }
            }
        }
    }
}

/// Editar los últimos 14 días.
struct JournalHistoryView: View {
    private var store: JournalStore { .shared }

    private var days: [Date] {
        (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: .now)) }
    }

    var body: some View {
        HalsynScreen {
            Text("Solo cuentan para el análisis los días registrados, aunque no marques nada: así HÅLSYN sabe que ese día no hubo ninguna de estas cosas.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
            ForEach(days, id: \.self) { day in
                HalsynCard {
                    VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                        HStack {
                            Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                                .font(.halsynHeadline)
                                .foregroundStyle(.halsynPrimaryText)
                            Spacer()
                            if store.tags(on: day) != nil {
                                Button("Quitar registro", role: .destructive) { store.clear(day) }
                                    .font(.halsynCaption)
                                    .buttonStyle(.borderless)
                            } else {
                                Button("Registrar sin nada") { store.set([], on: day) }
                                    .font(.halsynCaption)
                                    .buttonStyle(.borderless)
                            }
                        }
                        HabitChips(day: day)
                    }
                }
            }
        }
        .navigationTitle("Diario")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - INSIKT

struct HabitImpactCard: View {
    let impact: HabitImpact

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(spacing: HalsynSpacing.s) {
                    Image(systemName: impact.tag.systemImage)
                    Image(systemName: "arrow.right").font(.caption)
                    Image(systemName: impact.metric.systemImage)
                    Spacer()
                    if let favorable = impact.isFavorable {
                        HalsynStatusIndicator(favorable ? .positive : .caution, text: favorable ? "Favorable" : "Desfavorable")
                    }
                }
                .foregroundStyle(.halsynAccentText)
                Text(sentence)
                    .font(.halsynBody)
                    .foregroundStyle(.halsynPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HalsynGroupComparison(
                    lowLabel: String(localized: "Sin"),
                    highLabel: String(localized: "Con"),
                    lowValue: impact.withoutMean,
                    highValue: impact.withMean,
                    format: { InsightFormat.value($0, impact.metric) }
                )
                Text("Comparado en \(impact.withCount) días con y \(impact.withoutCount) sin. Es una asociación en tus datos, no prueba que una cosa cause la otra.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    private var sentence: LocalizedStringKey {
        let tag = String(localized: String.LocalizationValue(impact.tag.title))
        let with = InsightFormat.value(impact.withMean, impact.metric)
        let without = InsightFormat.value(impact.withoutMean, impact.metric)
        switch impact.metric {
        case .sleepDuration:
            return "Tras los días con «\(tag)» dormiste \(with) de media; tras los días sin, \(without)."
        case .heartRateVariability:
            return "La mañana después de «\(tag)» tu HRV fue de \(with) de media; sin, de \(without)."
        default:
            return "La mañana después de «\(tag)» tu FC en reposo fue de \(with) de media; sin, de \(without)."
        }
    }
}

/// Sección de INSIKT con lo que dice el diario.
struct HabitInsightsSection: View {
    @Environment(AppModel.self) private var model
    @State private var report: HabitReport?
    @State private var isExample = false
    private var store: JournalStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            HalsynSectionHeader("Tus hábitos", eyebrow: HalsynLexicon.tid.rawValue)
            if isExample {
                HalsynStatusIndicator(.neutral, text: "Diario de ejemplo (modo demo).")
            }
            if let report {
                ForEach(report.impacts) { HabitImpactCard(impact: $0) }
                if report.impacts.isEmpty || report.progress.contains(where: { !$0.isReady }) {
                    progressCard(report)
                }
            } else {
                HalsynLoadingState()
            }
        }
        .task(id: "\(model.reloadKey)|\(store.journal.hashValue)") {
            let source = store.journalForAnalysis(isDemo: model.isDemo)
            isExample = source.isExample
            report = await model.provider.habitReport(journal: source.journal, endingOn: .now, calendar: .current)
        }
    }

    private func progressCard(_ report: HabitReport) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                if report.loggedDays == 0 {
                    Text("Empieza el diario en HÄLSA. Hacen falta al menos 5 días con y 5 sin cada cosa para comparar.")
                        .font(.halsynBody)
                        .foregroundStyle(.halsynSecondaryText)
                } else {
                    Text("\(report.loggedDays) días registrados. Para comparar cada cosa hacen falta al menos 5 días con y 5 sin.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                    ForEach(report.progress) { item in
                        HStack(spacing: HalsynSpacing.s) {
                            Image(systemName: item.tag.systemImage)
                                .foregroundStyle(.halsynAccentText)
                                .frame(width: 20)
                            Text(LocalizedStringKey(item.tag.title))
                                .font(.halsynCaption)
                            Spacer()
                            if item.isReady {
                                Text("Sin diferencia clara por ahora")
                                    .font(.caption2)
                                    .foregroundStyle(.halsynSecondaryText)
                            } else {
                                Text("\(min(item.withCount, item.need))/\(item.need) con · \(min(item.withoutCount, item.need))/\(item.need) sin")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.halsynSecondaryText)
                            }
                        }
                    }
                }
            }
        }
    }
}
