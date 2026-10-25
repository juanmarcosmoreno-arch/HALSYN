import HalsynCore
import HalsynDesign
import SwiftUI

/// Texto redactado guardado por semana e idioma, para no generarlo cada vez.
struct WeeklyNarrativeCache: Codable {
    var weekEnd: Date
    var language: String
    var text: String

    static let key = "halsyn.weeklyNarrative"

    static func load(weekEnd: Date, language: String) -> String? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(WeeklyNarrativeCache.self, from: data),
              cache.weekEnd == weekEnd, cache.language == language else { return nil }
        return cache.text
    }

    static func save(_ text: String, weekEnd: Date, language: String) {
        if let data = try? JSONEncoder().encode(WeeklyNarrativeCache(weekEnd: weekEnd, language: language, text: text)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Valores ya formateados de cada dato, en el idioma y las unidades del usuario.
struct WeeklyFactText {
    let title: String
    let value: String
    let baseline: String?

    init(_ fact: WeeklyFact, unit: UnitSystem) {
        func format(_ number: Double) -> String {
            switch fact.metric {
            case .score, .restingHeartRate, .heartRateVariability, .steps, .exercise: HalsynFormat.integer(number)
            case .sleep: sleepText(number * 3600)
            case .running: HalsynFormat.decimal(number / unit.metersPerDistanceUnit, fractionDigits: 1) + " " + unit.distanceUnitSymbol
            }
        }
        switch fact.metric {
        case .score:
            title = String(localized: "Puntuación media")
            value = format(fact.value)
        case .sleep:
            title = String(localized: "Sueño por noche")
            value = format(fact.value)
        case .restingHeartRate:
            title = String(localized: "FC en reposo")
            value = format(fact.value) + " " + String(localized: "lpm")
        case .heartRateVariability:
            title = String(localized: "HRV")
            value = format(fact.value) + " ms"
        case .steps:
            title = String(localized: "Pasos al día")
            value = format(fact.value)
        case .exercise:
            title = String(localized: "Ejercicio en la semana")
            value = format(fact.value) + " min"
        case .running:
            title = String(localized: "Carreras")
            value = "\(fact.count ?? 0) · " + format(fact.value)
        }
        let unitSuffix: String = switch fact.metric {
        case .restingHeartRate: " " + String(localized: "lpm")
        case .heartRateVariability: " ms"
        case .exercise: " min"
        default: ""
        }
        baseline = fact.baseline.map { format($0) + unitSuffix }
    }

    /// Línea en inglés para el modelo (él redacta en el idioma del usuario).
    func promptLine(_ fact: WeeklyFact) -> String {
        let trend: String = switch fact.trend {
        case .up?: "higher than before" // nolocalize
        case .down?: "lower than before" // nolocalize
        case .similar?: "about the same as before" // nolocalize
        case nil: "no earlier data to compare" // nolocalize
        }
        let earlier = baseline.map { "; average of the previous 4 weeks: \($0)" } ?? "" // nolocalize
        return "- \(title): \(value)\(earlier) (\(trend))" // nolocalize
    }
}

// MARK: - Tarjeta

/// "Tu semana": los últimos 7 días completos frente a las 4 semanas
/// anteriores y, con Apple Intelligence, un resumen redactado en el iPhone
/// que solo puede usar estos números.
struct WeeklySummaryCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var review: WeeklyReview?
    @State private var narrative: String?
    @State private var writing = false
    @State private var status: OnDeviceNarrator.Status = .unavailable

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    HalsynSectionHeader("Tu semana", eyebrow: HalsynModule.insikt.brandName)
                    if model.isDemo { HalsynDemoBadge() }
                }
                if let review {
                    if review.facts.isEmpty {
                        Text("Aún no hay datos suficientes de esta semana.")
                            .font(.halsynBody)
                            .foregroundStyle(.halsynSecondaryText)
                    } else {
                        Text(verbatim: range(review))
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                        narrativeSection(review)
                        VStack(spacing: HalsynSpacing.s) {
                            ForEach(review.facts, id: \.metric) { fact in
                                row(fact)
                            }
                        }
                        Text("Frente a la media de tus 4 semanas anteriores. Los cambios pequeños se muestran como parecidos.")
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HalsynLoadingState()
                }
            }
        }
        .task(id: "\(model.reloadKey)|\(unitSystem.rawValue)") {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
            let loaded = await model.provider.weeklyReview(endingOn: yesterday, calendar: .current)
            review = loaded
            status = OnDeviceNarrator.status
            narrative = WeeklyNarrativeCache.load(weekEnd: loaded.end, language: OnDeviceNarrator.languageCode)
            if narrative == nil { await write(loaded) }
        }
    }

    // MARK: Redacción

    @ViewBuilder
    private func narrativeSection(_ review: WeeklyReview) -> some View {
        if let narrative {
            VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
                Text(verbatim: narrative)
                    .font(.halsynBody)
                    .foregroundStyle(.halsynPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline) {
                    Label("Redactado en tu iPhone con Apple Intelligence a partir de estos datos.", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                    Spacer(minLength: 4)
                    Button {
                        Task { await write(review, force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(writing)
                    .accessibilityLabel(Text("Volver a redactar"))
                }
            }
            .padding(HalsynSpacing.s)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.halsynAccent.opacity(0.08)))
        } else if writing {
            Label("Redactando tu resumen…", systemImage: "sparkles")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        } else {
            switch status {
            case .notEnabled:
                Text("Activa Apple Intelligence en Ajustes para ver además un resumen redactado.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            case .notReady:
                Text("Apple Intelligence se está preparando; el resumen redactado aparecerá más tarde.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            case .available, .unavailable:
                EmptyView()
            }
        }
    }

    private func write(_ review: WeeklyReview, force: Bool = false) async {
        guard status == .available, !review.facts.isEmpty, !writing else { return }
        writing = true
        defer { writing = false }
        let lines = review.facts.map { WeeklyFactText($0, unit: unitSystem).promptLine($0) }
        let prompt = "Facts for the user's last 7 days:\n" + lines.joined(separator: "\n") // nolocalize
        // Hasta dos intentos: si el texto trae un número que no está en los datos
        // o un término clínico, se descarta.
        for _ in 0..<2 {
            guard let text = await OnDeviceNarrator.write(instructions: Self.instructions, prompt: prompt) else { return }
            if GeneratedTextValidator.validate(text, allowedSources: lines) == nil {
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                narrative = clean
                WeeklyNarrativeCache.save(clean, weekEnd: review.end, language: OnDeviceNarrator.languageCode)
                return
            }
        }
        if force { narrative = nil }
    }

    private static var instructions: String {
        let language = OnDeviceNarrator.languageName
        return """
        You write a short weekly wellbeing summary for the user of a health and running app. \
        Write in \(language), speaking to the user informally in the second person singular. \
        Use 3 or 4 short sentences and at most 90 words, in plain text without lists, headings or emojis. \
        Use ONLY the facts provided. Copy every number exactly as it is written in the facts. \
        Do not calculate new numbers, percentages or differences, and do not add any other number. \
        Mention the most notable changes first and do not judge small changes. \
        Never diagnose, never mention diseases, symptoms, medication or treatments, and do not claim what caused a change. \
        Finish with one gentle, general suggestion that contains no numbers.
        """ // nolocalize
    }

    // MARK: Filas

    private func row(_ fact: WeeklyFact) -> some View {
        let text = WeeklyFactText(fact, unit: unitSystem)
        return HStack(alignment: .firstTextBaseline, spacing: HalsynSpacing.s) {
            Image(systemName: icon(fact.metric))
                .foregroundStyle(.halsynAccentText)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: text.title)
                    .font(.halsynCaption.weight(.semibold))
                    .foregroundStyle(.halsynPrimaryText)
                if let baseline = text.baseline {
                    Text("Antes: \(baseline)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: text.value)
                    .font(.halsynHeadline.monospacedDigit())
                    .foregroundStyle(.halsynPrimaryText)
                if let trend = fact.trend {
                    Label(trendText(trend), systemImage: trendIcon(trend))
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func trendText(_ trend: WeeklyFact.Trend) -> LocalizedStringKey {
        switch trend {
        case .up: "Más que antes"
        case .down: "Menos que antes"
        case .similar: "Parecido"
        }
    }

    private func trendIcon(_ trend: WeeklyFact.Trend) -> String {
        switch trend {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .similar: "equal"
        }
    }

    private func icon(_ metric: WeeklyMetric) -> String {
        switch metric {
        case .score: "sparkles"
        case .sleep: "moon.zzz"
        case .restingHeartRate: "heart"
        case .heartRateVariability: "waveform.path.ecg"
        case .steps: "figure.walk"
        case .exercise: "flame"
        case .running: "figure.run"
        }
    }

    private func range(_ review: WeeklyReview) -> String {
        let style = Date.FormatStyle().day().month(.abbreviated)
        return review.start.formatted(style) + " – " + review.end.formatted(style)
    }
}
