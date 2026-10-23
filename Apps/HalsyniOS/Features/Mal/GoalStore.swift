import Foundation
import HalsynCore
import HalsynDesign
import Observation
import UserNotifications

/// Objetivos del usuario: se guardan en el dispositivo y programan sus recordatorios.
@MainActor
@Observable
final class GoalStore {
    static let shared = GoalStore()

    private(set) var goals: [GoalDefinition]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        goals = GoalStorage.load(from: defaults)
    }

    func save(_ goal: GoalDefinition) {
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
        } else {
            goals.append(goal)
        }
        persist()
        Task { await GoalReminders.update(goal) }
    }

    func delete(_ goal: GoalDefinition) {
        goals.removeAll { $0.id == goal.id }
        persist()
        GoalReminders.cancel(goal)
    }

    func move(from source: IndexSet, to destination: Int) {
        goals.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        GoalStorage.save(goals, to: defaults)
    }
}

/// Recordatorios locales de objetivos. El aviso solo dice el objetivo
/// ("8.000 pasos"), nunca datos de salud ni el progreso.
enum GoalReminders {
    private static func identifiers(_ goal: GoalDefinition) -> [String] {
        (0...7).map { "halsyn.goal.\(goal.id.uuidString).\($0)" }
    }

    static func cancel(_ goal: GoalDefinition) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers(goal))
    }

    /// Programa (o quita) los avisos del objetivo. Devuelve `false` si no hay permiso.
    @discardableResult
    static func update(_ goal: GoalDefinition) async -> Bool {
        cancel(goal)
        guard let reminder = goal.reminder else { return true }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = "HÅLSYN"
        content.body = String(localized: "Recordatorio de tu objetivo: \(GoalText.title(goal, unit: .current))")
        let days: [Int?] = reminder.weekdays.isEmpty ? [nil] : reminder.weekdays.sorted().map { Optional($0) }
        for weekday in days {
            var components = DateComponents()
            components.hour = reminder.minutes / 60
            components.minute = reminder.minutes % 60
            components.weekday = weekday
            let request = UNNotificationRequest(
                identifier: "halsyn.goal.\(goal.id.uuidString).\(weekday ?? 0)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            try? await center.add(request)
        }
        return true
    }
}

extension UnitSystem {
    /// Unidades elegidas por el usuario en la app.
    static var current: UnitSystem {
        UserDefaults.standard.string(forKey: AppPreferences.unitSystemKey).flatMap(UnitSystem.init(rawValue:)) ?? .metric
    }
}

/// Textos de objetivos.
enum GoalText {
    /// Valor en la unidad mostrada, con su unidad ("8.000", "150 min", "20 km", "7 h 30 min").
    static func value(_ value: Double, _ kind: GoalKind, unit: UnitSystem) -> String {
        switch kind {
        case .steps, .runs: HalsynFormat.integer(value)
        case .exerciseMinutes: "\(HalsynFormat.integer(value)) min"
        case .distance, .runningDistance: "\(HalsynFormat.distance(meters: value, unit: unit)) \(unit.distanceUnitSymbol)"
        case .sleepAverage: sleepText(value * 3600)
        case .activeEnergy: "\(HalsynFormat.integer(value)) kcal"
        }
    }

    /// Título del objetivo ("8.000 pasos", "20 km corriendo"); el periodo va aparte.
    static func title(_ goal: GoalDefinition, unit: UnitSystem, target: Double? = nil) -> String {
        let amount = value(target ?? goal.target, goal.kind, unit: unit)
        switch goal.kind {
        case .steps: return String(localized: "\(amount) pasos")
        case .exerciseMinutes: return String(localized: "\(amount) de ejercicio")
        case .distance: return String(localized: "\(amount) caminando y corriendo")
        case .runningDistance: return String(localized: "\(amount) corriendo")
        case .runs: return String(localized: "\(amount) carreras")
        case .sleepAverage: return String(localized: "Dormir \(amount) de media")
        case .activeEnergy: return String(localized: "\(amount) de energía activa")
        }
    }

    static func period(_ period: Goal.Period) -> String {
        switch period {
        case .daily: String(localized: "Cada día")
        case .weekly: String(localized: "Cada semana")
        case .monthly: String(localized: "Cada mes")
        }
    }

    /// Paso del control de objetivo en la unidad base.
    static func step(_ kind: GoalKind, unit: UnitSystem) -> Double {
        switch kind {
        case .steps: 500
        case .exerciseMinutes: 10
        case .distance, .runningDistance: unit.metersPerDistanceUnit
        case .runs: 1
        case .sleepAverage: 0.25
        case .activeEnergy: 50
        }
    }

    static func range(_ kind: GoalKind, period: Goal.Period) -> ClosedRange<Double> {
        let factor: Double = period == .daily ? 1 : (period == .weekly ? 7 : 30)
        switch kind {
        case .steps: return 1000...(40_000 * factor)
        case .exerciseMinutes: return 10...(240 * factor)
        case .distance, .runningDistance: return 1000...(50_000 * factor)
        case .runs: return 1...(period == .weekly ? 14 : 60)
        case .sleepAverage: return 5...10
        case .activeEnergy: return 100...(2000 * factor)
        }
    }
}
