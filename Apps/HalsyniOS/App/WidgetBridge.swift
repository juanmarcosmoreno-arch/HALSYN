import Foundation
import HalsynCore
import WidgetKit

/// Deja el resumen del día para los widgets y les pide que se redibujen.
enum WidgetBridge {
    @MainActor
    static func publish(_ snapshot: HalsaSnapshot, isDemo: Bool, now: Date = .now) {
        guard let defaults = WidgetSnapshotStore.sharedDefaults() else { return }
        let goal = snapshot.goal.map { item in
            WidgetSnapshot.GoalSummary(
                title: GoalText.title(item.definition, unit: .current, target: item.progress.target),
                fraction: item.progress.fraction,
                isCompleted: item.progress.isCompleted
            )
        }
        let widget = WidgetSnapshot(
            updatedAt: now,
            score: snapshot.score?.value,
            scoreBand: snapshot.score.map { NSLocalizedString($0.band.title, comment: "") },
            recovery: snapshot.recovery?.value,
            steps: snapshot.stepsToday,
            sleepHours: snapshot.sleepHours,
            goal: goal,
            isDemo: isDemo
        )
        WidgetSnapshotStore.save(widget, to: defaults)
        WidgetCenter.shared.reloadAllTimelines()
        // El reloj muestra esta misma puntuación (tiene menos historial para calcularla).
        RunSettingsStore.shared.shareDaily(widget)
    }
}
