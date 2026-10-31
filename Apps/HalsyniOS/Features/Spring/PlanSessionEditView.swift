import HalsynCore
import HalsynDesign
import SwiftUI

/// Cambiar un día de la semana actual del plan: moverlo o intercambiarlo con
/// otro día, alargarlo o acortarlo, o no correr. Si el día está libre, traer
/// una sesión de otro día. Las semanas siguientes se reajustan solas cada lunes.
struct PlanSessionEditView: View {
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    private var store: TrainingPlanStore { .shared }
    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            Form {
                if let plan = store.plan, plan.canEdit(day, today: .now, calendar: calendar) {
                    let session = plan.session(on: day, calendar: calendar)
                    summarySection(session)
                    if let session, session.kind != .rest {
                        if let volume = session.volume {
                            volumeSection(session, volume: volume)
                        }
                        moveSection(plan, session: session)
                        Section {
                            Button(role: .destructive) {
                                if store.edit({ $0.skipping(sessionOn: day, today: .now, calendar: calendar) }) { dismiss() }
                            } label: {
                                Label(calendar.isDateInToday(day) ? LocalizedStringKey("Hoy no corro") : LocalizedStringKey("Ese día no corro"), systemImage: "bed.double")
                            }
                        } footer: {
                            Text("Queda como descanso. Si prefieres hacerla otro día, muévela arriba.")
                        }
                    } else {
                        bringSection(plan)
                    }
                } else {
                    Text("Solo se puede cambiar la semana actual, de hoy en adelante. Las semanas siguientes se reajustan solas cada lunes con lo que corriste.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
            .navigationTitle(Text(day, format: .dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    private func summarySection(_ session: PlannedSession?) -> some View {
        Section {
            if let session, session.kind != .rest {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(session.kind.title)).font(.halsynHeadline)
                        Text(verbatim: SessionText.detail(session, unit: unitSystem))
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                } icon: {
                    Image(systemName: session.kind.systemImage)
                }
            } else {
                Label("Sin carrera este día", systemImage: "bed.double")
            }
        } footer: {
            Text("Los cambios valen para esta semana. Las siguientes se reajustan cada lunes con lo que corriste.")
        }
    }

    // MARK: Más corta o más larga

    private func volumeSection(_ session: PlannedSession, volume: PlannedSession.Volume) -> some View {
        Section {
            Stepper {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: volumeText(volume))
                        .font(.halsynBody.monospacedDigit())
                    if let duration = session.estimatedDuration {
                        Text("Unos \(HalsynFormat.duration(duration)) en total")
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
            } onIncrement: {
                change(session, to: step(volume, by: 1))
            } onDecrement: {
                change(session, to: step(volume, by: -1))
            }
        } header: {
            Text("Más corta o más larga")
        } footer: {
            Text("El ritmo no cambia: solo cuánto dura. Acortar un día no se recupera otro; el plan sigue con lo que hagas.")
        }
    }

    private func volumeText(_ volume: PlannedSession.Volume) -> String {
        switch volume {
        case let .distance(meters):
            SessionText.distance(meters, unit: unitSystem)
        case let .repeats(count):
            String(localized: "\(count) series")
        case let .block(meters):
            String(localized: "Bloque de \(SessionText.distance(meters, unit: unitSystem))")
        }
    }

    private func step(_ volume: PlannedSession.Volume, by direction: Int) -> PlannedSession.Volume {
        switch volume {
        case let .distance(meters): .distance(meters + Double(direction) * 1000)
        case let .repeats(count): .repeats(count + direction)
        case let .block(meters): .block(meters + Double(direction) * 500)
        }
    }

    private func change(_ session: PlannedSession, to volume: PlannedSession.Volume) {
        let updated = session.with(volume)
        guard updated != session else { return }
        store.edit { $0.replacing(sessionOn: day, with: updated, today: .now, calendar: calendar) }
    }

    // MARK: Mover o traer

    private func otherDays(_ plan: TrainingPlan) -> [Date] {
        plan.editableDays(today: .now, calendar: calendar).filter { !calendar.isDate($0, inSameDayAs: day) }
    }

    private func moveSection(_ plan: TrainingPlan, session: PlannedSession) -> some View {
        Section {
            ForEach(otherDays(plan), id: \.self) { other in
                Button {
                    if store.edit({ $0.moving(sessionOn: day, to: other, today: .now, calendar: calendar) }) { dismiss() }
                } label: {
                    dayRow(other, plan: plan, action: moveAction(other, plan: plan))
                }
            }
        } header: {
            Text("Hacerla otro día")
        } footer: {
            Text("Si ese día ya tiene una sesión, se intercambian. Evita poner dos sesiones duras seguidas.")
        }
    }

    private func moveAction(_ other: Date, plan: TrainingPlan) -> LocalizedStringKey {
        if let session = plan.session(on: other, calendar: calendar), session.kind != .rest {
            return "Intercambiar"
        }
        return "Mover aquí"
    }

    private func bringSection(_ plan: TrainingPlan) -> some View {
        let candidates = otherDays(plan).filter { plan.session(on: $0, calendar: calendar).map { $0.kind != .rest } ?? false }
        return Section {
            if candidates.isEmpty {
                Text("No quedan sesiones esta semana para traer.")
                    .foregroundStyle(.halsynSecondaryText)
            }
            ForEach(candidates, id: \.self) { other in
                Button {
                    if store.edit({ $0.moving(sessionOn: other, to: day, today: .now, calendar: calendar) }) { dismiss() }
                } label: {
                    dayRow(other, plan: plan, action: "Traer")
                }
            }
        } header: {
            Text("Traer una sesión de otro día")
        } footer: {
            Text("Ese otro día queda libre.")
        }
    }

    private func dayRow(_ other: Date, plan: TrainingPlan, action: LocalizedStringKey) -> some View {
        let session = plan.session(on: other, calendar: calendar)
        let isGym = plan.goal.gymWeekdays?.contains(calendar.component(.weekday, from: other)) == true
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(other, format: .dateTime.weekday(.wide).day())
                    .foregroundStyle(.halsynPrimaryText)
                Group {
                    if let session, session.kind != .rest {
                        Text(LocalizedStringKey(session.kind.title))
                    } else if isGym {
                        Text("Libre (gimnasio)")
                    } else {
                        Text("Libre")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
            }
            Spacer()
            Text(action)
                .font(.halsynCaption)
                .foregroundStyle(.halsynAccentText)
        }
    }
}
