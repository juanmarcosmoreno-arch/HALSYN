import HalsynCore
import HalsynDesign
import SwiftUI

/// El plan de entrenamiento en el reloj (llega del iPhone con los ajustes):
/// la sesión de hoy arriba y los próximos días; cada sesión se explica y se
/// empieza desde aquí.
struct WatchPlanSection: View {
    let snapshot: PlanSnapshot
    private var calendar: Calendar { .current }

    var body: some View {
        Section {
            if let today = snapshot.upcoming(from: .now, calendar: calendar).first(where: { calendar.isDateInToday($0.date) }) {
                NavigationLink {
                    WatchPlanSessionView(session: today)
                } label: {
                    WatchPlanRow(session: today, showsDay: false)
                }
            } else {
                Label("Hoy no hay carrera", systemImage: "bed.double")
                    .font(.footnote)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            }
            NavigationLink {
                WatchPlanView(snapshot: snapshot)
            } label: {
                Label("Próximos días", systemImage: "calendar")
            }
        } header: {
            Text(verbatim: header)
        }
    }

    private var header: String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: snapshot.raceDate)).day ?? 0
        let race = Bundle.main.localizedString(forKey: snapshot.distance.title, value: nil, table: nil)
        return days >= 0 ? String(localized: "Plan · \(race) · faltan \(days) días") : String(localized: "Plan · \(race)")
    }
}

struct WatchPlanView: View {
    let snapshot: PlanSnapshot

    var body: some View {
        List {
            ForEach(snapshot.upcoming(from: .now, calendar: .current), id: \.date) { session in
                NavigationLink {
                    WatchPlanSessionView(session: session)
                } label: {
                    WatchPlanRow(session: session, showsDay: true)
                }
            }
        }
        .navigationTitle("Plan")
    }
}

struct WatchPlanRow: View {
    let session: PlannedSession
    let showsDay: Bool
    private var unitSystem: UnitSystem { RunSettingsStore.shared.settings.unitSystem }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsDay {
                Text(session.date, format: .dateTime.weekday(.wide).day())
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
            }
            Label {
                Text(LocalizedStringKey(session.kind.title))
            } icon: {
                Image(systemName: session.kind.systemImage)
                    .foregroundStyle(session.kind.isHard ? Color(HalsynPalette.alertDark) : Color(HalsynPalette.darkAccent))
            }
            if session.kind != .rest {
                Text(verbatim: SessionText.detail(session, unit: unitSystem))
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                    .lineLimit(2)
            }
        }
    }
}

/// Una sesión: qué es, para qué sirve y empezar.
struct WatchPlanSessionView: View {
    let session: PlannedSession
    @Environment(WorkoutManager.self) private var workout
    private var unitSystem: UnitSystem { RunSettingsStore.shared.settings.unitSystem }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.date, format: .dateTime.weekday(.wide).day().month())
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                Label(LocalizedStringKey(session.kind.title), systemImage: session.kind.systemImage)
                    .font(.headline)
                    .foregroundStyle(Color(HalsynPalette.darkAccent))
                if session.kind != .rest {
                    Text(verbatim: SessionText.detail(session, unit: unitSystem))
                        .font(.footnote)
                }
                Text(LocalizedStringKey(session.kind.explanation))
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                if let plan = intervalPlan {
                    Button {
                        Task { await workout.start(indoor: false, plan: plan) }
                    } label: {
                        Label("Empezar al aire libre", systemImage: "figure.run")
                    }
                    .tint(Color(HalsynPalette.darkAccent))
                    Button {
                        Task { await workout.start(indoor: true, plan: plan) }
                    } label: {
                        Label("Empezar en cinta", systemImage: "figure.run.treadmill")
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(Text(LocalizedStringKey(session.kind.title)))
    }

    private var intervalPlan: IntervalPlan? {
        let name = Bundle.main.localizedString(forKey: session.kind.title, value: nil, table: nil)
        return PlanAdaptation.intervalPlan(for: session, id: "halsyn-plan-session", name: name)
    }
}
