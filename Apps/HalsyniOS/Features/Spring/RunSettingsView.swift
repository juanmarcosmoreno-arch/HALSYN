import AVFoundation
import HalsynCore
import HalsynDesign
import SwiftUI

/// Enlace de un ajuste de SPRING: lee de `RunSettingsStore` y guarda (y envía al reloj) al cambiar.
@MainActor
func runSetting<Value>(_ keyPath: WritableKeyPath<RunSettings, Value>) -> Binding<Value> {
    let store = RunSettingsStore.shared
    return Binding(
        get: { store.settings[keyPath: keyPath] },
        set: { value in store.update { $0[keyPath: keyPath] = value } }
    )
}

/// SPRING › Ajustes de carrera. Todo se guarda al momento y se envía al Apple Watch.
struct RunSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    private var store: RunSettingsStore { .shared }
    private var settings: RunSettings { store.settings }

    var body: some View {
        Form {
            screensSection
            lapsSection
            Section {
                NavigationLink {
                    ZoneSettingsView()
                } label: {
                    LabeledContent {
                        Text(zonesSummary)
                    } label: {
                        Label("Zonas cardíacas", systemImage: "heart")
                    }
                }
                NavigationLink {
                    AlertSettingsView()
                } label: {
                    LabeledContent {
                        Text(alertsSummary)
                    } label: {
                        Label("Alertas", systemImage: "bell.badge")
                    }
                }
            } header: {
                Text("Durante la carrera")
            }
            intervalsSection
            watchSection
        }
        .navigationTitle("Ajustes de carrera")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
    }

    // MARK: Pantallas

    private var screensSection: some View {
        Section {
            ForEach(settings.screens) { profile in
                NavigationLink {
                    ScreenEditorView(profileID: profile.id)
                } label: {
                    HStack(spacing: HalsynSpacing.m) {
                        WatchScreenPreview(profile: profile.normalized())
                            .frame(width: 54)
                            .allowsHitTesting(false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: profile.name)
                                .font(.halsynHeadline)
                            Text(verbatim: profile.normalized().fields.map { NSLocalizedString($0.title, comment: "") }.joined(separator: " · "))
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .onMove { from, to in
                store.update { $0.screens.move(fromOffsets: from, toOffset: to) }
            }
            .onDelete { offsets in
                store.update { settings in
                    settings.screens.remove(atOffsets: offsets)
                    if settings.screens.isEmpty { settings.screens = [.easyRun] }
                }
            }
            if settings.screens.count < RunSettings.maximumScreens {
                Button {
                    store.update { settings in
                        let number = settings.screens.count + 1
                        settings.screens.append(WorkoutScreenProfile(
                            id: "screen-\(UUID().uuidString)",
                            name: String(localized: "Pantalla \(number)"),
                            layout: .three,
                            fields: [.distance, .currentPace, .heartRate]
                        ))
                    }
                } label: {
                    Label("Añadir pantalla", systemImage: "plus")
                }
            }
        } header: {
            HStack {
                Text("Pantallas del reloj")
                Spacer()
                EditButton().font(.caption)
            }
        } footer: {
            Text("Durante la carrera se pasa de una a otra deslizando en horizontal. Hasta 4 pantallas.")
        }
    }

    // MARK: Vueltas

    private var lapsSection: some View {
        Section {
            Picker(selection: runSetting(\.autoLapDistance)) {
                ForEach(RunSettings.autoLapOptions, id: \.self) { option in
                    Text(autoLapTitle(option)).tag(option)
                }
            } label: {
                Label("Vuelta automática", systemImage: "flag")
            }
            Toggle(isOn: runSetting(\.isVoiceEnabled)) {
                Label("Avisos de voz", systemImage: "speaker.wave.2")
            }
            if settings.isVoiceEnabled {
                Picker(selection: runSetting(\.voiceRoute)) {
                    Text("iPhone (auriculares del teléfono)").tag(VoiceOutput.phone)
                    Text("Reloj").tag(VoiceOutput.watch)
                } label: {
                    Label("Dónde suena", systemImage: "headphones")
                }
                LabeledContent {
                    Text(verbatim: voiceDescription)
                } label: {
                    Label("Voz", systemImage: "person.wave.2")
                }
                Button {
                    CoachSpeaker.shared.say(String(localized: "Kilómetro 1. Así sonarán los avisos durante la carrera."))
                } label: {
                    Label("Probar la voz", systemImage: "play.circle")
                }
            }
        } footer: {
            Text("El botón Vuelta del reloj marca vueltas manuales en cualquier momento. Con los avisos de voz se dice cada vuelta con su ritmo y su pulso, cada serie y recuperación y las alertas. En el iPhone suenan por los auriculares conectados al teléfono y bajan la música un momento; si el iPhone no está cerca, habla el reloj. Para una voz más natural, descarga una voz mejorada en Ajustes › Accesibilidad › Contenido leído › Voces.")
        }
    }

    /// "Paulina · México" con la voz que usará el iPhone.
    private var voiceDescription: String {
        guard let voice = CoachSpeech.bestVoice() else { return "—" }
        let region = Locale(identifier: voice.language).region.flatMap { Locale.current.localizedString(forRegionCode: $0.identifier) }
        return [voice.name, region].compactMap { $0 }.joined(separator: " · ")
    }

    private func autoLapTitle(_ distance: Double?) -> LocalizedStringKey {
        guard let distance else { return "Desactivada" }
        if distance == 1609.344 { return "Cada milla" }
        if distance < 1000 { return "Cada \(Int(distance)) m" }
        return "Cada \(Int(distance / 1000)) km"
    }

    // MARK: Intervalos

    private var intervalsSection: some View {
        Section {
            ForEach(settings.intervalPlans) { plan in
                NavigationLink {
                    IntervalPlanEditorView(planID: plan.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: plan.name).font(.halsynHeadline)
                        Text(verbatim: IntervalPlanFormatter.summary(plan, unit: unitSystem))
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
            }
            .onDelete { offsets in
                store.update { $0.intervalPlans.remove(atOffsets: offsets) }
            }
            Button {
                store.update { settings in
                    settings.intervalPlans.append(IntervalPlan(
                        id: "plan-\(UUID().uuidString)",
                        name: String(localized: "Mis intervalos"),
                        warmup: .time(600),
                        work: .distance(800),
                        recovery: .time(120),
                        repeats: 4,
                        cooldown: .time(300)
                    ))
                }
            } label: {
                Label("Nuevo plan de intervalos", systemImage: "plus")
            }
        } header: {
            Text("Intervalos")
        } footer: {
            Text("Los planes aparecen en SPRING › Intervalos en el reloj. El reloj vibra al empezar cada serie y cada recuperación.")
        }
    }

    // MARK: Reloj

    private var watchSection: some View {
        Section {
            switch store.link {
            case .ready:
                HalsynStatusIndicator(.positive, text: "Los cambios se envían al Apple Watch automáticamente.")
            case .appNotInstalled:
                HalsynStatusIndicator(.caution, text: "Instala HÅLSYN en el Apple Watch para recibir estos ajustes.")
            case .noWatch:
                HalsynStatusIndicator(.caution, text: "No hay ningún Apple Watch emparejado.")
            case .unsupported, .unknown:
                HalsynStatusIndicator(.neutral, text: "Se enviarán al Apple Watch cuando esté disponible.")
            }
        } footer: {
            Text("Solo se envían preferencias, nunca datos de salud.")
        }
    }

    // MARK: Resúmenes

    private var zonesSummary: LocalizedStringKey {
        guard let max = settings.zones.zones.last?.upperBound else { return "Sin configurar" }
        return "FC máx. \(Int(max)) lpm"
    }

    private var alertsSummary: LocalizedStringKey {
        switch (settings.alerts.paceEnabled, settings.alerts.zoneEnabled) {
        case (true, true): "Ritmo y zona"
        case (true, false): "Ritmo"
        case (false, true): "Zona"
        case (false, false): "Desactivadas"
        }
    }
}

// MARK: - Editor de pantalla

struct ScreenEditorView: View {
    let profileID: String
    @Environment(\.dismiss) private var dismiss
    private var store: RunSettingsStore { .shared }

    private var index: Int? { store.settings.screens.firstIndex { $0.id == profileID } }

    var body: some View {
        if let index {
            let profile = store.settings.screens[index].normalized()
            Form {
                Section {
                    HStack {
                        Spacer()
                        WatchScreenPreview(profile: profile)
                            .frame(width: 170)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Vista previa con valores de ejemplo.")
                        .frame(maxWidth: .infinity)
                }

                Section {
                    TextField("Nombre", text: Binding(
                        get: { profile.name },
                        set: { name in update(index) { $0.name = name.isEmpty ? $0.name : String(name.prefix(24)) } }
                    ))
                    Picker("Campos en pantalla", selection: Binding(
                        get: { profile.layout },
                        set: { layout in update(index) { $0 = $0.withLayout(layout) } }
                    )) {
                        ForEach(WorkoutScreenLayout.allCases, id: \.self) { layout in
                            Text(verbatim: "\(layout.fieldCount)").tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(Array(profile.fields.enumerated()), id: \.offset) { slot, field in
                        Picker(selection: Binding(
                            get: { field },
                            set: { newField in update(index) { $0 = $0.replacing(fieldAt: slot, with: newField) } }
                        )) {
                            ForEach(WorkoutFieldKind.allCases) { kind in
                                Text(LocalizedStringKey(kind.title)).tag(kind)
                            }
                        } label: {
                            Text("Campo \(slot + 1)")
                        }
                    }
                } header: {
                    Text("Campos")
                } footer: {
                    Text("Si eliges un campo que ya está en otra posición, se intercambian. Sin dato en vivo se muestra «--»: cadencia (pendiente de verificar en dispositivo), potencia si tu reloj no la mide, zona sin FC máxima configurada, objetivo e intervalo fuera de un plan.")
                }
            }
            .navigationTitle(Text(verbatim: profile.name))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            HalsynEmptyState(systemImage: "rectangle.dashed", title: "Pantalla eliminada", message: "Vuelve a Ajustes de carrera.")
        }
    }

    private func update(_ index: Int, _ change: (inout WorkoutScreenProfile) -> Void) {
        store.update { settings in
            guard settings.screens.indices.contains(index) else { return }
            change(&settings.screens[index])
        }
    }
}

// MARK: - Zonas

struct ZoneSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var observedMax: Double?
    @State private var latestResting: Double?
    @State private var loaded = false
    private var store: RunSettingsStore { .shared }
    private var zones: HeartRateZoneConfiguration { store.settings.zones }

    var body: some View {
        Form {
            Section {
                Picker("Método", selection: runSetting(\.zones.method)) {
                    ForEach(HeartRateZoneMethod.allCases) { method in
                        Text(LocalizedStringKey(method.title)).tag(method)
                    }
                }
                Picker("FC máxima", selection: runSetting(\.zones.maxSource)) {
                    ForEach(MaxHeartRateSource.allCases) { source in
                        Text(LocalizedStringKey(source.title)).tag(source)
                    }
                }
                switch zones.maxSource {
                case .manual:
                    bpmField("FC máxima (lpm)", value: runSetting(\.zones.maxHeartRate))
                case .observed:
                    observedRow
                }
                if zones.method == .heartRateReserve {
                    bpmField("FC en reposo (lpm)", value: runSetting(\.zones.restingHeartRate))
                    if let latestResting, !model.isDemo {
                        Button("Usar la de Apple Health: \(Int(latestResting)) lpm") {
                            store.update { $0.zones.restingHeartRate = latestResting.rounded() }
                        }
                    }
                }
            } footer: {
                Text("No se estima la FC máxima por la edad: introdúcela (por ejemplo, de una prueba de esfuerzo) o usa la más alta registrada en tus carreras.")
            }

            Section {
                if zones.zones.isEmpty {
                    Text("Define tu FC máxima para ver las zonas.")
                        .foregroundStyle(.halsynSecondaryText)
                } else {
                    ForEach(zones.zones) { zone in
                        LabeledContent {
                            Text(verbatim: "\(Int(zone.lowerBound))–\(Int(zone.upperBound)) lpm")
                                .monospacedDigit()
                        } label: {
                            HStack(spacing: HalsynSpacing.s) {
                                HalsynZoneBadge(zone: zone.index)
                                Text(LocalizedStringKey(zone.name))
                            }
                        }
                    }
                    if zones.method == .heartRateReserve && zones.effectiveMethod == .percentOfMax {
                        HalsynStatusIndicator(.caution, text: "Falta una FC en reposo válida: se usa el porcentaje de la FC máxima.")
                    }
                }
            } header: {
                Text("Tus zonas")
            } footer: {
                Text("Modelo de 5 zonas: empiezan al 50, 60, 70, 80 y 90 por ciento. Es una convención de entrenamiento, no una indicación médica. Si tienes una condición cardíaca, consulta a un profesional.")
            }
        }
        .navigationTitle("Zonas cardíacas")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
        .task(id: model.reloadKey) {
            guard !model.isDemo else {
                observedMax = nil
                latestResting = nil
                loaded = true
                return
            }
            observedMax = HeartRateZoneConfiguration.observedMax(in: await model.provider.recentWorkouts(limit: 60))
            if case let .available(reading) = await model.provider.latest(.restingHeartRate, on: .now) {
                latestResting = reading.value
            }
            loaded = true
            applyObserved()
        }
        .onChange(of: zones.maxSource) { _, _ in applyObserved() }
    }

    @ViewBuilder
    private var observedRow: some View {
        if model.isDemo {
            Text("Disponible al conectar Apple Health: en modo demo no se guardan valores de ejemplo como tuyos.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        } else if let observedMax {
            LabeledContent("Máxima registrada") {
                Text(verbatim: "\(Int(observedMax)) lpm").monospacedDigit()
            }
        } else if loaded {
            Text("Aún no hay carreras con FC registrada.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        } else {
            ProgressView()
        }
    }

    private func applyObserved() {
        guard zones.maxSource == .observed, !model.isDemo, let observedMax else { return }
        store.update { $0.zones.maxHeartRate = observedMax.rounded() }
    }

    private func bpmField(_ title: LocalizedStringKey, value: Binding<Double?>) -> some View {
        LabeledContent(title) {
            TextField("lpm", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 90)
        }
    }
}

// MARK: - Alertas

struct AlertSettingsView: View {
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    private var store: RunSettingsStore { .shared }
    private var alerts: RunAlertConfiguration { store.settings.alerts }

    var body: some View {
        Form {
            Section {
                Toggle("Alerta de ritmo", isOn: runSetting(\.alerts.paceEnabled))
                if alerts.paceEnabled {
                    PaceStepper(title: "Más rápido que", seconds: runSetting(\.alerts.paceRange.fastest), unit: unitSystem, bounds: 150...(alerts.paceRange.slowest - 5))
                    PaceStepper(title: "Más lento que", seconds: runSetting(\.alerts.paceRange.slowest), unit: unitSystem, bounds: (alerts.paceRange.fastest + 5)...900)
                }
            } footer: {
                Text("En carreras libres. En intervalos manda el ritmo objetivo de cada serie.")
            }

            Section {
                Toggle("Alerta de zona cardíaca", isOn: runSetting(\.alerts.zoneEnabled))
                    .disabled(store.settings.zones.zones.isEmpty)
                if alerts.zoneEnabled {
                    Stepper(value: runSetting(\.alerts.lowestZone), in: 1...alerts.highestZone) {
                        LabeledContent("Desde", value: "Z\(alerts.lowestZone)")
                    }
                    Stepper(value: runSetting(\.alerts.highestZone), in: alerts.lowestZone...5) {
                        LabeledContent("Hasta", value: "Z\(alerts.highestZone)")
                    }
                }
            } footer: {
                if store.settings.zones.zones.isEmpty {
                    Text("Configura primero tus zonas cardíacas.")
                }
            }

            Section {
                Label("El reloj vibra tras 10 s fuera de rango y repite cada minuto mientras sigas fuera. También avisa cuando vuelves al rango.", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .navigationTitle("Alertas")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
    }
}

/// Ritmo editable de 5 en 5 segundos en la unidad elegida (se guarda en s/km).
struct PaceStepper: View {
    let title: LocalizedStringKey
    @Binding var seconds: Double
    let unit: UnitSystem
    /// Límites en s/km (el "más rápido" no puede superar al "más lento").
    var bounds: ClosedRange<Double> = 150...900

    private var step: Double { 5 * 1000 / unit.metersPerDistanceUnit }

    var body: some View {
        Stepper {
            LabeledContent(title) {
                Text(verbatim: "\(Pace(secondsPerKilometer: seconds).formatted(in: unit)) \(unit.paceUnitSymbol)")
                    .monospacedDigit()
            }
        } onIncrement: {
            seconds = min(seconds + step, bounds.upperBound)
        } onDecrement: {
            seconds = max(seconds - step, bounds.lowerBound)
        }
    }
}

// MARK: - Editor de intervalos

struct IntervalPlanEditorView: View {
    let planID: String
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    private var store: RunSettingsStore { .shared }
    private var index: Int? { store.settings.intervalPlans.firstIndex { $0.id == planID } }

    var body: some View {
        if let index {
            let plan = store.settings.intervalPlans[index]
            Form {
                Section {
                    TextField("Nombre", text: Binding(
                        get: { plan.name },
                        set: { name in update(index) { $0.name = name.isEmpty ? $0.name : String(name.prefix(30)) } }
                    ))
                    Text(verbatim: IntervalPlanFormatter.summary(plan, unit: unitSystem))
                        .font(.halsynCaption.monospacedDigit())
                        .foregroundStyle(.halsynSecondaryText)
                }

                optionalGoalSection("Calentamiento", goal: plan.warmup) { goal in update(index) { $0.warmup = goal } }

                Section {
                    Stepper(value: Binding(get: { plan.repeats }, set: { value in update(index) { $0.repeats = value } }), in: IntervalPlan.repeatsRange) {
                        LabeledContent("Repeticiones", value: "\(plan.repeats)")
                    }
                    GoalEditor(title: "Serie", goal: Binding(get: { plan.work }, set: { goal in update(index) { $0.work = goal } }), unit: unitSystem)
                    Toggle("Ritmo objetivo", isOn: Binding(
                        get: { plan.workPace != nil },
                        set: { on in update(index) { $0.workPace = on ? PaceRange(fastest: 270, slowest: 285) : nil } }
                    ))
                    if let pace = plan.workPace {
                        PaceStepper(title: "Más rápido que", seconds: Binding(get: { pace.fastest }, set: { value in update(index) { $0.workPace = PaceRange(fastest: value, slowest: pace.slowest) } }), unit: unitSystem, bounds: 150...(pace.slowest - 5))
                        PaceStepper(title: "Más lento que", seconds: Binding(get: { pace.slowest }, set: { value in update(index) { $0.workPace = PaceRange(fastest: pace.fastest, slowest: value) } }), unit: unitSystem, bounds: (pace.fastest + 5)...900)
                    }
                    if plan.repeats > 1 {
                        GoalEditor(title: "Recuperación", goal: Binding(get: { plan.recovery }, set: { goal in update(index) { $0.recovery = goal } }), unit: unitSystem)
                    }
                } header: {
                    Text("Series")
                } footer: {
                    Text("Con ritmo objetivo, el reloj avisa si vas más rápido o más lento durante la serie.")
                }

                optionalGoalSection("Vuelta a la calma", goal: plan.cooldown) { goal in update(index) { $0.cooldown = goal } }
            }
            .navigationTitle(Text(verbatim: plan.name))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            HalsynEmptyState(systemImage: "repeat", title: "Plan eliminado", message: "Vuelve a Ajustes de carrera.")
        }
    }

    private func optionalGoalSection(_ title: LocalizedStringKey, goal: IntervalGoal?, set: @escaping (IntervalGoal?) -> Void) -> some View {
        Section {
            Toggle(title, isOn: Binding(get: { goal != nil }, set: { set($0 ? .time(600) : nil) }))
            if let goal {
                GoalEditor(title: "Duración", goal: Binding(get: { goal }, set: { set($0) }), unit: unitSystem)
            }
        }
    }

    private func update(_ index: Int, _ change: (inout IntervalPlan) -> Void) {
        store.update { settings in
            guard settings.intervalPlans.indices.contains(index) else { return }
            change(&settings.intervalPlans[index])
        }
    }
}

/// Objetivo de un paso: por tiempo, por distancia o abierto (hasta pulsar Vuelta).
struct GoalEditor: View {
    let title: LocalizedStringKey
    @Binding var goal: IntervalGoal
    let unit: UnitSystem

    private enum Kind: Hashable { case time, distance, open }

    private var kind: Kind {
        switch goal {
        case .time: .time
        case .distance: .distance
        case .open: .open
        }
    }

    var body: some View {
        Picker(title, selection: Binding(get: { kind }, set: { newKind in
            switch newKind {
            case .time: goal = .time(120)
            case .distance: goal = .distance(400)
            case .open: goal = .open
            }
        })) {
            Text("Tiempo").tag(Kind.time)
            Text("Distancia").tag(Kind.distance)
            Text("Hasta pulsar Vuelta").tag(Kind.open)
        }
        switch goal {
        case let .time(seconds):
            Stepper {
                LabeledContent("Tiempo", value: IntervalPlanFormatter.goal(goal, unit: unit))
            } onIncrement: {
                goal = .time(min(seconds + (seconds >= 300 ? 60 : 15), 3600))
            } onDecrement: {
                goal = .time(max(seconds - (seconds > 300 ? 60 : 15), 15))
            }
        case let .distance(meters):
            Stepper {
                LabeledContent("Distancia", value: IntervalPlanFormatter.goal(goal, unit: unit))
            } onIncrement: {
                goal = .distance(min(meters + (meters >= 2000 ? 500 : 100), 20_000))
            } onDecrement: {
                goal = .distance(max(meters - (meters > 2000 ? 500 : 100), 100))
            }
        case .open:
            EmptyView()
        }
    }
}
