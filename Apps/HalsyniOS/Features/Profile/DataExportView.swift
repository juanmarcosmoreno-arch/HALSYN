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
                Text("Se arman tres archivos: tus entrenamientos (una fila por carrera, caminata o salida en bici), tus datos de cada día (pulso en reposo, HRV, sueño, pasos, peso, VO₂ máx. y más) y un resumen con tu plan, tu objetivo y tus tests. Todo se genera en el iPhone; nada se envía a ningún lado hasta que tú lo compartes.")
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

        let workoutsCSV = DataExport.workoutsCSV(workouts, marks: marks, shoes: shoes, calendar: calendar)
        let dailyCSV = DataExport.dailyCSV(series: series, healthScores: health, recoveryScores: recovery, sleep: sleep, days: days, calendar: calendar)
        let summary = await summaryText(start: start, end: end, workouts: workouts)

        let stamp = isoDay(end)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HALSYN-\(stamp)", isDirectory: true)  // nolocalize
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = [
            (folder.appendingPathComponent("halsyn-resumen-\(stamp).md"), summary),  // nolocalize
            (folder.appendingPathComponent("halsyn-entrenamientos-\(stamp).csv"), workoutsCSV),  // nolocalize
            (folder.appendingPathComponent("halsyn-diario-\(stamp).csv"), dailyCSV),  // nolocalize
        ]
        var written: [URL] = []
        for (url, text) in files where (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
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
    private func summaryText(start: Date, end: Date, workouts: [WorkoutSummary]) async -> String {
        let calendar = Calendar.current
        var lines: [String] = []
        lines.append("# HÅLSYN")
        lines.append(String(localized: "Exportado el \(end.formatted(date: .long, time: .shortened)). Período: \(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))."))
        if model.isDemo {
            lines.append("")
            lines.append(String(localized: "ATENCIÓN: son datos de demostración (sintéticos), no datos reales."))
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
               let probability = GoalProbability.evaluate(plan: plan, performance: performance, runs: runs, today: end, calendar: calendar) {
                let category = GoalProbabilityText.titleText(probability.category)
                let projectedRange = GoalProbabilityText.range(probability.projectedRange)
                lines.append("- " + String(localized: "Tiempo estimado hoy: \(HalsynFormat.duration(probability.currentTime))") + (probability.currentRange.map { " (" + String(localized: "rango orientativo") + " \(GoalProbabilityText.range($0)))" } ?? ""))
                lines.append("- " + String(localized: "Tiempo proyectado el día de la carrera: \(HalsynFormat.duration(probability.projectedTime)) (rango orientativo \(projectedRange), sin calibrar con resultados reales)"))
                lines.append("- " + String(localized: "Factibilidad: \(category). \(GoalProbabilityText.confidence(probability.confidence))."))
                if let adherence = probability.adherence {
                    let sessions = adherence.sessionsSummary ?? "—"
                    lines.append("- " + String(localized: "Sesiones programadas cumplidas (desde el inicio del plan, máx. 4 semanas): \(sessions)"))
                    let partialText = String(adherence.partial), missedText = String(adherence.missed), excusedText = String(adherence.excused)
                    lines.append("- " + String(localized: "Sesiones hechas en parte: \(partialText); no hechas: \(missedText); no hechas por enfermedad o lesión (no cuentan): \(excusedText)"))
                    let weeksText = String(adherence.weeksWithPlan)
                    lines.append("- " + String(localized: "Frecuencia: \(HalsynFormat.decimal(adherence.actualRunsPerWeek, fractionDigits: 1)) carreras por semana reales frente a \(String(adherence.targetRunsPerWeek)) del objetivo; \(String(adherence.runsOutsidePlan)) fuera del plan; semanas con plan: \(weeksText)"))
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
                case .belowEstimate: role = String(localized: "no cuenta: por debajo de tu forma, no la baja")
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
            let duplicateIDs = Set(RacePerformanceModel.deduplicated(results, calendar: calendar).duplicates.map(\.0.id))
            for result in results.prefix(20) {
                let kind = result.kind == .test ? String(localized: "Test") : String(localized: "Carrera")
                let note = duplicateIDs.contains(result.id) ? " · " + String(localized: "duplicado: cuenta una sola vez") : ""
                lines.append("- \(result.date.formatted(date: .abbreviated, time: .omitted)) · \(kind) · \(DataExport.number(result.distance / 1000, digits: 2)) km · \(HalsynFormat.duration(result.time))" + note)  // nolocalize
            }
        }

        lines.append("")
        lines.append("## " + String(localized: "Archivos"))
        lines.append("- " + String(localized: "Entrenamientos: una fila por entrenamiento. Distancia en km, duración en minutos, ritmo en min/km y s/km, pulso en lpm, cadencia en pasos por minuto, desnivel en m, potencia en W, temperatura en °C y humedad en %. «marked_as» indica si lo marcaste como test o carrera."))
        lines.append("- " + String(localized: "Diario: una fila por día con lo que hay en Salud (vacío = sin dato): pulso en reposo, HRV (SDNN, ms), respiración, VO₂ máx., SpO₂ en %, pasos, distancia, energía activa, ejercicio, sueño en horas y sus fases, peso, grasa, temperatura de muñeca (desvío) y luz del día. «health_score» y «recovery_score» son puntuaciones de HÅLSYN de 0 a 100, orientativas y no clínicas."))
        return lines.joined(separator: "\n") + "\n"
    }
}
