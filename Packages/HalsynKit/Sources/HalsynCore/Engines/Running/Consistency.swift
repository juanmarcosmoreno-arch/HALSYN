import Foundation

/// Una semana (lunes a domingo) del análisis de constancia.
public struct ConsistencyWeek: Hashable, Identifiable, Sendable {
    public let start: Date
    public let runs: Int
    public let distance: Double
    /// Con 4 días o más de enfermedad o lesión: no cuenta.
    public let excused: Bool
    /// Semana de descarga, afinamiento o carrera del plan: menos volumen es lo previsto.
    public let light: Bool

    public var id: Date { start }
}

/// Constancia del entrenamiento con su fórmula a la vista.
public struct ConsistencyReport: Hashable, Sendable {
    public enum Component: String, Hashable, Sendable, CaseIterable {
        /// Carreras por semana frente al objetivo.
        case frequency
        /// Semanas con el mínimo de carreras.
        case regularity
        /// Variación del volumen semanal (sin semanas livianas ni excusadas).
        case stability
        /// Sesiones del plan cumplidas.
        case plan
    }

    public struct Part: Hashable, Sendable {
        public let component: Component
        /// 0–1.
        public let value: Double
        /// Peso en el puntaje (ya repartido si falta el plan).
        public let weight: Double
    }

    /// 0–100; `nil` con menos de 4 semanas de historial.
    public let score: Int?
    public let parts: [Part]
    public let weeks: [ConsistencyWeek]
    public let targetPerWeek: Int
    /// Semanas seguidas (hasta la actual) con al menos una carrera; las excusadas no cortan.
    public let streakWeeks: Int
    /// Pausas de 10 días o más sin correr en las 12 semanas (sin contar enfermedad o lesión).
    public let interruptions: Int
    public let longestGapDays: Int
}

/// Constancia: regularidad más allá del porcentaje de cumplimiento del plan.
///
/// Puntaje (0–100) = suma ponderada de cuatro partes, cada una de 0 a 1:
/// - **Frecuencia** (35 %): carreras por semana ÷ objetivo, como mucho 1.
/// - **Regularidad** (25 %): semanas con al menos (objetivo − 1, mínimo 1) carreras;
///   en las semanas livianas del plan basta con una.
/// - **Estabilidad** (20 %): 1 − coeficiente de variación del volumen semanal
///   (sin semanas livianas ni excusadas), entre 0 y 1.
/// - **Plan** (20 %): sesiones del plan cumplidas (adherencia); sin plan, su
///   peso se reparte entre las otras.
///
/// No penaliza: semanas con 4 días o más de enfermedad o lesión (se quitan),
/// semanas de descarga o afinamiento del plan (solo piden una carrera y no
/// cuentan para la estabilidad), ni los descansos programados.
/// Últimas 8 semanas completas más la actual; hacen falta 4 con datos.
public enum ConsistencyEngine {
    public static let version = "1.0"
    public static let weeks = 8
    public static let minimumWeeks = 4
    public static let gapDays = 10
    public static let excusedDaysPerWeek = 4
    public static let weights: [ConsistencyReport.Component: Double] = [.frequency: 0.35, .regularity: 0.25, .stability: 0.20, .plan: 0.20]

    public static func evaluate(
        runs: [(date: Date, distance: Double)],
        targetPerWeek: Int,
        excusedDays: Set<Date> = [],
        lightWeekStarts: Set<Date> = [],
        planAdherence: Double? = nil,
        today: Date,
        calendar: Calendar
    ) -> ConsistencyReport {
        var calendar = calendar
        calendar.firstWeekday = 2
        let target = max(targetPerWeek, 1)
        let todayStart = calendar.startOfDay(for: today)
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: todayStart)?.start ?? todayStart
        let excused = Set(excusedDays.map { calendar.startOfDay(for: $0) })
        let light = Set(lightWeekStarts.map { calendar.dateInterval(of: .weekOfYear, for: $0)?.start ?? $0 })
        let firstRun = runs.map(\.date).min()

        // Semanas completas (la actual no cuenta para el puntaje, sí para la racha).
        var rows: [ConsistencyWeek] = []
        for offset in (1...weeks).reversed() {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { continue }
            // Antes de la primera carrera no hay historial que evaluar.
            if let firstRun, end <= calendar.startOfDay(for: firstRun) { continue }
            let inWeek = runs.filter { $0.date >= start && $0.date < end }
            let sickDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.filter { excused.contains($0) }.count
            rows.append(ConsistencyWeek(start: start, runs: inWeek.count, distance: inWeek.map(\.distance).reduce(0, +), excused: sickDays >= excusedDaysPerWeek, light: light.contains(start)))
        }
        let counted = rows.filter { !$0.excused }

        // Racha (de la semana actual hacia atrás; la actual vale si ya corriste).
        var streak = 0
        var week = currentWeek
        var isCurrent = true
        while let end = calendar.date(byAdding: .day, value: 7, to: week) {
            let ran = runs.contains { $0.date >= week && $0.date < end }
            let sick = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week) }.filter { excused.contains($0) }.count >= excusedDaysPerWeek
            if ran { streak += 1 } else if !(isCurrent || sick) { break }
            isCurrent = false
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week), streak < 104 else { break }
            if let firstRun, previous < calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: firstRun)) ?? firstRun { break }
            week = previous
        }

        // Pausas largas en 12 semanas (los días de enfermedad o lesión no cuentan).
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -12, to: todayStart) ?? todayStart
        let days = runs.map { calendar.startOfDay(for: $0.date) }.filter { $0 >= windowStart }
        let boundaries = Array(Set(days)).sorted() + [todayStart]
        var interruptions = 0, longest = 0
        var previousDay = max(windowStart, firstRun.map { calendar.startOfDay(for: $0) } ?? windowStart)
        for day in boundaries {
            let span = (calendar.dateComponents([.day], from: previousDay, to: day).day ?? 0)
            let sick = (0..<max(span, 0)).compactMap { calendar.date(byAdding: .day, value: $0, to: previousDay) }.filter { excused.contains($0) }.count
            let gap = span - sick
            longest = max(longest, gap)
            if gap >= gapDays { interruptions += 1 }
            previousDay = day
        }

        guard counted.count >= minimumWeeks else {
            return ConsistencyReport(score: nil, parts: [], weeks: rows, targetPerWeek: target, streakWeeks: streak, interruptions: interruptions, longestGapDays: longest)
        }
        let frequency = min(Double(counted.map(\.runs).reduce(0, +)) / Double(counted.count) / Double(target), 1)
        let regular = counted.filter { $0.runs >= ($0.light ? 1 : max(target - 1, 1)) }.count
        let regularity = Double(regular) / Double(counted.count)
        let steady = counted.filter { !$0.light }.map(\.distance)
        var stability = 1.0
        if steady.count >= 2 {
            let mean = steady.reduce(0, +) / Double(steady.count)
            let sd = (steady.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(steady.count - 1)).squareRoot()
            stability = mean > 0 ? max(0, 1 - sd / mean) : 0
        }
        var values: [(ConsistencyReport.Component, Double)] = [(.frequency, frequency), (.regularity, regularity), (.stability, stability)]
        if let planAdherence { values.append((.plan, min(max(planAdherence, 0), 1))) }
        let totalWeight = values.map { weights[$0.0] ?? 0 }.reduce(0, +)
        let parts = values.map { ConsistencyReport.Part(component: $0.0, value: $0.1, weight: (weights[$0.0] ?? 0) / totalWeight) }
        let score = Int((parts.map { $0.value * $0.weight }.reduce(0, +) * 100).rounded())
        return ConsistencyReport(score: score, parts: parts, weeks: rows, targetPerWeek: target, streakWeeks: streak, interruptions: interruptions, longestGapDays: longest)
    }
}
