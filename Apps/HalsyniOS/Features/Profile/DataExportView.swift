import HalsynCore
import HalsynDesign
import SwiftUI
import UIKit

/// Exportar los datos crudos (entrenamientos y signos vitales por día) en CSV,
/// más un resumen en texto para pegar en una IA y seguir tu progreso.
struct DataExportView: View {
    enum Period: Int, CaseIterable, Identifiable {
        case quarter = 90
        case year = 365
        case threeYears = 1095

        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .quarter: "Últimos 90 días"
            case .year: "Último año"
            case .threeYears: "Últimos 3 años"
            }
        }
    }

    struct Export {
        let files: [URL]
        let text: String
        let workouts: Int
        let days: Int
    }

    @Environment(AppModel.self) private var model
    @State private var period: Period = .year
    @State private var isWorking = false
    @State private var export: Export?
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Picker("Período", selection: $period) {
                    ForEach(Period.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .onChange(of: period) { _, _ in export = nil }
                Button {
                    Task { await prepare() }
                } label: {
                    HStack {
                        Label("Preparar los archivos", systemImage: "tablecells")
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isWorking)
            } footer: {
                Text("Se arman tres archivos: tus entrenamientos (una fila por carrera, caminata o salida en bici), tus datos de cada día (pulso en reposo, HRV, sueño, pasos, peso, VO₂ máx. y más) y un resumen con tu plan, tu objetivo y tus tests. Si los hay, también las pruebas del modelo con sus pesos, tus eventos de salud y tus valores de laboratorio. Todo se genera en el iPhone; nada se envía a ningún lado hasta que tú lo compartes.")
            }

            if let export {
                Section {
                    LabeledContent("Entrenamientos", value: String(export.workouts))
                    LabeledContent("Días", value: String(export.days))
                    ShareLink(items: export.files) {
                        Label("Compartir o guardar los archivos", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = export.text
                        copied = true
                    } label: {
                        Label(copied ? LocalizedStringKey("Copiado") : LocalizedStringKey("Copiar todo como texto para una IA"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                } header: {
                    Text("Listo")
                } footer: {
                    Text("Para una IA: pega el texto (o adjunta los archivos) y pregúntale, por ejemplo, «¿Cómo vengo con mi preparación?» o «¿Qué relación ves entre mi sueño y mis ritmos?». Repite la exportación cada tanto para que vea tu progreso. La IA puede equivocarse: no reemplaza a un profesional.")
                }
            }
        }
        .navigationTitle("Exportar mis datos")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Datos

    private func prepare() async {
        isWorking = true
        copied = false
        defer { isWorking = false }
        let calendar = Calendar.current
        let end = Date.now
        let count = period.rawValue
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: calendar.startOfDay(for: end)) ?? end
        let provider = model.provider

        var series: [MetricSeries] = []
        for kind in DataExport.dailyKinds {
            series.append(await provider.dailySeries(kind, days: count, endingOn: end))
        }
        let health = await provider.dailyScores(endingOn: end, days: count)
        let recoveryEstimates = await provider.recoveryEstimates(endingOn: end, days: count)
        var recovery: [Date: Int] = [:]
        for estimate in recoveryEstimates {
            if let value = estimate.value { recovery[estimate.day] = value }
        }
        let sleep = await provider.sleepNights(endingOn: end, days: count)
        var seen = Set<UUID>()
        let workouts = (await provider.recentWorkouts(limit: 5000) + (await provider.recentRides(limit: 5000)))
            .filter { $0.start >= start && seen.insert($0.id).inserted }
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }

        var marks: [UUID: String] = [:]
        for result in FitnessStore.shared.results {
            if let id = result.workoutID { marks[id] = result.kind == .test ? "test" : "race" }
        }
        var shoes: [UUID: String] = [:]
        let closet = ShoeStore.shared.closet
        for workout in workouts {
            if let shoe = closet.shoe(for: workout) { shoes[workout.id] = shoe.name }
        }

        // Datos calculados por HÅLSYN para cada entrenamiento (sin muestras: la
        // clasificación de series necesita el pulso segundo a segundo).
        let quality = DataQuality.assess(workouts)
        // Pulso segundo a segundo de las carreras de las últimas 6 semanas, para
        // detectar series igual que en la pantalla del entrenamiento.
        let samplesStart = calendar.date(byAdding: .day, value: -42, to: end) ?? end
        var samples: [UUID: [HeartRatePoint]] = [:]
        for run in workouts.filter({ $0.activity.isRun && $0.start >= samplesStart && $0.averageHeartRate != nil }).prefix(60) {
            let points = await provider.workoutDetail(for: run).heartRate
            if !points.isEmpty { samples[run.id] = points }
        }
        let intensities = IntensityContext.intensities(workouts, samples: samples)
        let runs = workouts.filter(\.activity.isRun)
        let performance = FitnessStore.shared.performance(runs: runs, today: end)
        var evidenceByWorkout: [UUID: PerformanceEvidence] = [:]
        for item in performance?.evidence ?? [] {
            if let result = FitnessStore.shared.results.first(where: { $0.id == item.id }), let workoutID = result.workoutID {
                evidenceByWorkout[workoutID] = item
            } else {
                evidenceByWorkout[item.id] = item
            }
        }
        var extras: [UUID: DataExport.WorkoutExtra] = [:]
        for workout in workouts {
            let intensity = intensities[workout.id]
            let evidence = evidenceByWorkout[workout.id]
            var extra = DataExport.WorkoutExtra(
                intensity: intensity.map { DataExport.code($0.kind) } ?? "",
                intensityBasis: intensity.map { $0.kind == .unknown ? "" : $0.basis.rawValue } ?? "",
                qualityFlags: quality[workout.id]?.flags.map(DataExport.code) ?? [],
                modelRole: evidence.map { DataExport.code($0.role) } ?? "",
                modelWeight: evidence?.weight,
                sessionType: intensity?.sessionType?.rawValue ?? "",
                vdotEligibility: workout.activity.isRun ? DataExport.code(IntensityContext.eligibility(workout)) : ""
            )
            extra.harderThanPlanned = intensity?.harderThanPlanned == true
            extras[workout.id] = extra
        }
        let workoutsCSV = DataExport.workoutsCSV(workouts, marks: marks, shoes: shoes, extras: extras, calendar: calendar)
        let dailyCSV = DataExport.dailyCSV(series: series, healthScores: health, recoveryScores: recovery, sleep: sleep, days: days, calendar: calendar)
        let summary = await summaryText(start: start, end: end, workouts: workouts, sleep: sleep)

        let stamp = isoDay(end)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HALSYN-\(stamp)", isDirectory: true)  // nolocalize
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = [
            (folder.appendingPathComponent("halsyn-resumen-\(stamp).md"), summary),  // nolocalize
            (folder.appendingPathComponent("halsyn-entrenamientos-\(stamp).csv"), workoutsCSV),  // nolocalize
            (folder.appendingPathComponent("halsyn-diario-\(stamp).csv"), dailyCSV),  // nolocalize
        ]
        var extraFiles: [(URL, String)] = []
        if let performance {
            extraFiles.append((folder.appendingPathComponent("halsyn-pruebas-\(stamp).csv"), DataExport.evidenceCSV(performance, results: FitnessStore.shared.results, calendar: calendar)))  // nolocalize
        }
        if !FitnessStore.shared.results.isEmpty {
            extraFiles.append((folder.appendingPathComponent("halsyn-resultados-\(stamp).csv"), DataExport.resultsCSV(FitnessStore.shared.results, distinct: FitnessStore.shared.distinct, calendar: calendar)))  // nolocalize
        }
        if !HealthEventStore.shared.events.isEmpty {
            extraFiles.append((folder.appendingPathComponent("halsyn-eventos-\(stamp).csv"), DataExport.healthEventsCSV(HealthEventStore.shared.events, calendar: calendar)))  // nolocalize
        }
        if !LabResultStore.shared.results.isEmpty {
            extraFiles.append((folder.appendingPathComponent("halsyn-laboratorio-\(stamp).csv"), DataExport.labResultsCSV(LabResultStore.shared.results, calendar: calendar)))  // nolocalize
        }
        var written: [URL] = []
        for (url, text) in files + extraFiles where (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
            written.append(url)
        }
        let text = summary
            + "\n\n## " + String(localized: "Entrenamientos (CSV)") + "\n\n```csv\n" + workoutsCSV + "```\n"  // nolocalize
            + "\n## " + String(localized: "Datos de cada día (CSV)") + "\n\n```csv\n" + dailyCSV + "```\n"  // nolocalize
        export = Export(files: written, text: text, workouts: workouts.count, days: days.count)
    }

    private func isoDay(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Resumen en Markdown: perfil, objetivo, forma, tests y qué hay en cada archivo.
    private func summaryText(start: Date, end: Date, workouts: [WorkoutSummary], sleep: [SleepNight]) async -> String {
        let calendar = Calendar.current
        var lines: [String] = []
        lines.append("# HÅLSYN")
        lines.append(String(localized: "Exportado el \(end.formatted(date: .long, time: .shortened)). Período: \(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))."))
        if model.isDemo {
            lines.append("")
            lines.append(String(localized: "ATENCIÓN: son datos de demostración (sintéticos), no datos reales."))
        }

        lines.append("")
        lines.append("## " + String(localized: "Cálculo"))
        lines.append("- " + String(localized: "Calculado el \(end.formatted(date: .numeric, time: .standard)) en el iPhone, sin servicios externos."))
        lines.append("- " + "RacePerformanceModel \(RacePerformanceModel.version) · RecoveryEngine \(RecoveryEngine.version) · HealthScoreEngine \(HealthScoreEngine.version) · " + String(localized: "formato de exportación") + " \(DataExport.formatVersion)")  // nolocalize
        let exportRuns = workouts.filter(\.activity.isRun)
        let observedMax = HeartRateZoneConfiguration.observedMax(in: exportRuns)
        let effectiveMax = FitnessStore.shared.maxHeartRate(for: exportRuns)
        if let configured = FitnessStore.shared.configuredMaxHeartRate, effectiveMax.overridden, let used = effectiveMax.value {
            let configuredText = String(Int(configured)), usedText = String(Int(used))
            lines.append("- " + String(localized: "FC máxima de referencia: \(usedText) lpm, observada. La configurada a mano (\(configuredText) lpm) queda por debajo de lo que registraste y haría parecer muy intensos los rodajes: se usa la observada hasta que la revises."))
        } else if let configured = FitnessStore.shared.configuredMaxHeartRate {
            let configuredText = String(Int(configured))
            let observedText = observedMax.map { String(Int($0)) } ?? "—"
            lines.append("- " + String(localized: "FC máxima de referencia: \(configuredText) lpm, configurada a mano (la más alta registrada en el período: \(observedText) lpm). Las intensidades y la elegibilidad para el VDOT se calculan con la configurada."))
        } else if let reference = EffortClassifier.referenceMaxHeartRate(configured: nil, runs: exportRuns) {
            let referenceText = String(Int(reference))
            lines.append("- " + String(localized: "FC máxima de referencia: \(referenceText) lpm, observada (la segunda más alta de tus carreras, para no tomar un pico del sensor)."))
        }
        let workoutSources = Set(workouts.map { DataExport.source($0.origin) }).sorted().joined(separator: ", ")
        let sleepSources = Set(sleep.compactMap(\.sourceName)).sorted().joined(separator: ", ")
        let workoutSourcesText = workoutSources.isEmpty ? "—" : workoutSources
        let sleepSourcesText = sleepSources.isEmpty ? "—" : sleepSources
        lines.append("- " + String(localized: "Fuentes de los entrenamientos: \(workoutSourcesText)"))
        lines.append("- " + String(localized: "Fuentes del sueño: \(sleepSourcesText)"))
        let computedWorkouts = DataExport.computedWorkoutColumns.joined(separator: ", ")
        let computedDaily = DataExport.computedDailyColumns.joined(separator: ", ")
        lines.append("- " + String(localized: "Datos originales y calculados: las columnas vienen tal cual de Apple Health o de lo que cargaste, salvo las calculadas por HÅLSYN. Entrenamientos: \(computedWorkouts). Diario: \(computedDaily)."))
        lines.append("- " + String(localized: "«record_id» es un código corto derivado del identificador del registro: sirve para ver duplicados sin exponer el identificador de Salud. Un dato ausente queda vacío; nunca se rellena con 0."))

        let summary = DataExport.qualitySummary(workouts)
        lines.append("")
        lines.append("## " + String(localized: "Calidad de los datos"))
        if summary.isEmpty {
            lines.append("- " + String(localized: "Sin avisos en los entrenamientos del período."))
        } else {
            for item in summary {
                lines.append("- \(item.code): \(String(item.count))")  // nolocalize
            }
            lines.append("- " + String(localized: "Nada se borra: los registros marcados siguen en el CSV con su aviso en «quality_flags». duplicate/overlaps no cuentan para nada; missing_distance, too_short e implausible_pace no cuentan para la forma; implausible_hr y las cadencias imposibles solo descartan ese valor."))
        }
        let flaggedNights = sleep.filter { !$0.flags.isEmpty }.count
        if flaggedNights > 0 {
            let nightsText = String(flaggedNights)
            lines.append("- " + String(localized: "Noches con algo a revisar (siesta sumada, registro corto, fragmentado o varias fuentes): \(nightsText); ver «sleep_flags» en el diario."))
        }

        lines.append("")
        lines.append("## " + String(localized: "Perfil"))
        let characteristics = await model.provider.userCharacteristics()
        let birth = ProfileDefaults.birthDate() ?? characteristics.birthDate
        if let birth, let age = calendar.dateComponents([.year], from: birth, to: end).year {
            lines.append("- " + String(localized: "Edad: \(String(age)) años"))
        }
        if let sex = characteristics.sex {
            let sexText = sex == .female ? String(localized: "mujer") : String(localized: "hombre")
            lines.append("- " + String(localized: "Sexo: \(sexText)"))
        }
        let heightCm = UserDefaults.standard.double(forKey: "halsyn.profile.heightCm")
        if heightCm > 0 {
            lines.append("- " + String(localized: "Altura: \(String(Int(heightCm.rounded()))) cm"))
        } else if let meters = characteristics.heightMeters {
            lines.append("- " + String(localized: "Altura: \(String(Int((meters * 100).rounded()))) cm"))
        }

        let runs = workouts.filter { $0.activity.isRun }
        let estimate = FitnessStore.shared.estimate(runs: runs)
        if let plan = TrainingPlanStore.shared.plan {
            lines.append("")
            lines.append("## " + String(localized: "Objetivo y plan"))
            let distance = String(localized: String.LocalizationValue(plan.goal.distance.title))
            lines.append("- " + String(localized: "Carrera: \(distance) el \(plan.goal.raceDate.formatted(date: .long, time: .omitted))"))
            if let goal = plan.goal.goalTime {
                lines.append("- " + String(localized: "Tiempo objetivo: \(HalsynFormat.duration(goal))"))
            }
            lines.append("- " + String(localized: "Carreras por semana: \(String(plan.goal.runsPerWeek))"))
            if let performance = FitnessStore.shared.performance(runs: runs, today: end),
               let probability = GoalProbability.evaluateInApp(plan: plan, performance: performance, runs: runs, today: end, calendar: calendar) {
                let category = GoalProbabilityText.titleText(probability.category)
                let projectedRange = GoalProbabilityText.range(probability.projectedRange)
                lines.append("- " + String(localized: "Tiempo estimado hoy: \(HalsynFormat.duration(probability.currentTime))") + (probability.currentRange.map { " (" + String(localized: "rango orientativo") + " \(GoalProbabilityText.range($0)))" } ?? ""))
                lines.append("- " + String(localized: "Tiempo proyectado el día de la carrera: \(HalsynFormat.duration(probability.projectedTime)) (rango orientativo \(projectedRange), sin calibrar con resultados reales)"))
                lines.append("- " + String(localized: "Factibilidad: \(category). \(GoalProbabilityText.confidence(probability.confidence))."))
                for line in PredictionExplanationText.projection(probability, goal: plan.goal).dropFirst() {
                    lines.append("  - " + line)  // nolocalize
                }
                if let adherence = probability.adherence {
                    let sessions = adherence.sessionsSummary ?? "—"
                    lines.append("- " + String(localized: "Sesiones programadas cumplidas (desde el inicio del plan, máx. 4 semanas): \(sessions)"))
                    let partialText = String(adherence.partial), missedText = String(adherence.missed), excusedText = String(adherence.excused)
                    lines.append("- " + String(localized: "Sesiones hechas en parte: \(partialText); no hechas: \(missedText); no hechas por enfermedad o lesión (no cuentan): \(excusedText)"))
                    let weeksText = String(adherence.weeksWithPlan)
                    lines.append("- " + String(localized: "Frecuencia: \(HalsynFormat.decimal(adherence.actualRunsPerWeek, fractionDigits: 1)) carreras por semana reales frente a \(String(adherence.targetRunsPerWeek)) del objetivo; \(String(adherence.runsOutsidePlan)) fuera del plan; semanas con plan: \(weeksText)"))
                    for line in AdherenceText.lines(adherence) {
                        lines.append("  - " + line)  // nolocalize
                    }
                }
            }
        }
        if let estimate {
            lines.append("")
            lines.append("## " + String(localized: "Forma actual"))
            let dateText = estimate.date.formatted(date: .abbreviated, time: .omitted)
            if estimate.combinedFrom > 1 {
                let count = estimate.combinedFrom
                lines.append("- " + String(localized: "VDOT (Daniels): \(RaceGoalText.vdot(estimate.vdot)), media ponderada de \(count) pruebas (ver «Pruebas que usa el modelo»); la más reciente es del \(dateText). Cada prueba conserva su propio VDOT: el valor combinado no tiene por qué coincidir con ninguno."))
            } else {
                let sourceText = estimate.isFromTraining ? String(localized: "estimado de entrenamientos") : String(localized: "de un test o carrera")
                lines.append("- " + String(localized: "VDOT (Daniels): \(RaceGoalText.vdot(estimate.vdot)), \(sourceText) del \(dateText)"))
            }
        }
        if let performance = FitnessStore.shared.performance(runs: runs, today: end), !performance.evidence.isEmpty {
            lines.append("")
            lines.append("## " + String(localized: "Pruebas que usa el modelo"))
            for item in performance.evidence.prefix(20) {
                let role: String
                switch item.role {
                case .counted: role = String(localized: "cuenta (peso \(HalsynFormat.decimal(item.weight, fractionDigits: 2)))")
                case .belowEstimate: role = String(localized: "no cuenta: esfuerzo no confirmado por debajo de tu forma (si fue a tope, confírmalo como test)")
                case .notMaximal: role = String(localized: "no cuenta: más de 3 puntos por debajo de tus tests, probablemente no fue a tope")
                case .duplicate: role = String(localized: "no cuenta: duplicado")
                case .inconsistent: role = String(localized: "pesa menos: no encaja con el resto")
                }
                let factorText = item.factors.map { item.weight > 0 ? " = " + PredictionExplanationText.factors($0) : "" } ?? ""
                lines.append("- \(item.date.formatted(date: .abbreviated, time: .omitted)) · \(DataExport.number(item.distance / 1000, digits: 2)) km · \(HalsynFormat.duration(item.time)) · VDOT \(RaceGoalText.vdot(item.vdot)) · \(role)\(factorText)")  // nolocalize
            }
        }
        let results = FitnessStore.shared.results
        if !results.isEmpty {
            lines.append("")
            lines.append("## " + String(localized: "Tests y carreras registrados"))
            let duplicateOf = Dictionary(FitnessStore.shared.duplicates.map { ($0.0.id, $0.keptID) }, uniquingKeysWith: { first, _ in first })
            for result in results.prefix(20) {
                let kind = result.kind == .test ? String(localized: "Test") : String(localized: "Carrera")
                let origin = result.workoutID == nil ? String(localized: "cargado a mano") : String(localized: "de un entrenamiento") + " " + (result.workoutID.map(DataExport.recordID) ?? "")
                let note = duplicateOf[result.id].map { " · " + String(localized: "duplicado de") + " " + DataExport.recordID($0) + ": " + String(localized: "cuenta una sola vez") } ?? ""
                lines.append("- \(result.date.formatted(date: .abbreviated, time: .omitted)) · \(kind) · \(DataExport.number(result.distance / 1000, digits: 2)) km · \(HalsynFormat.duration(result.time)) · \(DataExport.recordID(result.id)) · \(origin)" + note)  // nolocalize
            }
            lines.append("- " + String(localized: "Cada resultado tiene su record_id; los que vienen de un entrenamiento indican también el record_id de ese entrenamiento en el CSV de entrenamientos. Los cargados a mano no tienen fila en ese CSV: están en halsyn-resultados."))
        }

        let events = HealthEventStore.shared.events
        if !events.isEmpty {
            lines.append("")
            lines.append("## " + String(localized: "Eventos de salud registrados"))
            for event in events.prefix(30) {
                let name = event.title.isEmpty ? String(localized: String.LocalizationValue(event.kind.title)) : event.title
                lines.append("- \(name) · \(HealthEventText.period(event))")  // nolocalize
            }
            lines.append("- " + String(localized: "Son contexto que registraste tú: HÅLSYN no diagnostica ni atribuye causas."))
        }
        let labs = LabResultStore.shared.results
        if !labs.isEmpty {
            lines.append("")
            lines.append("## " + String(localized: "Valores cardiometabólicos"))
            for result in labs.prefix(30) {
                lines.append("- \(result.date.formatted(date: .abbreviated, time: .omitted)) · \(LabText.title(result)) · \(LabText.value(result))")  // nolocalize
            }
        }
        lines.append("")
        lines.append("## " + String(localized: "Archivos"))
        lines.append("- " + String(localized: "Entrenamientos: una fila por entrenamiento. Distancia en km, duración en minutos, ritmo en min/km y s/km, pulso en lpm, cadencia en pasos por minuto, desnivel en m, potencia en W, temperatura en °C y humedad en %. «marked_as» indica si lo marcaste como test o carrera."))
        lines.append("- " + String(localized: "Diario: una fila por día con lo que hay en Salud (vacío = sin dato): pulso en reposo, HRV (SDNN, ms), respiración, VO₂ máx., SpO₂ en %, pasos, distancia, energía activa, ejercicio, sueño en horas y sus fases, peso, grasa, temperatura de muñeca (desvío) y luz del día. «health_score» y «recovery_score» son puntuaciones de HÅLSYN de 0 a 100, orientativas y no clínicas."))
        lines.append("- " + String(localized: "Entrenamientos, columnas calculadas: «intensity» es la intensidad fisiológica (recovery, easy, moderate, tempo, intervals, very_hard, test, race) e «intensity_basis» con qué se decidió; «session_type», el tipo de sesión (plan o estructura); «vdot_eligibility», si sirve para el VDOT (confirmed, candidate o not_eligible y el motivo); «model_role» y «model_weight», el papel y el peso en el modelo; «harder_than_planned», una sesión suave del plan hecha con intensidad alta. Un pulso alto (very_hard) no significa esfuerzo máximo."))
        lines.append("- " + String(localized: "Diario: «nap_h» son horas de siesta incluidas en «sleep_h»; «sleep_start» y «sleep_end» son del sueño principal."))
        lines.append("- " + String(localized: "Pruebas (si hay): cada prueba del modelo con su VDOT, su papel, su peso y los factores (tipo × antigüedad × distancia × calidad × tope × coherencia). Eventos y laboratorio (si hay): lo que registraste."))
        return lines.joined(separator: "\n") + "\n"
    }
}
