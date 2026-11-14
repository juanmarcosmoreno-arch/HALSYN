import Foundation

/// Exportación de datos crudos en CSV (para hojas de cálculo o para pegar en
/// una IA). Columnas en inglés con la unidad en el nombre, punto decimal y
/// fechas ISO, para que cualquier herramienta las lea sin ambigüedad.
public enum DataExport {
    /// Versión del formato de exportación (columnas nuevas siempre al final).
    public static let formatVersion = "5"

    /// Columnas que calcula HÅLSYN (el resto viene tal cual de Apple Health o de lo que cargaste).
    public static let computedWorkoutColumns = ["pace_min_km", "pace_s_per_km", "intensity", "intensity_basis", "quality_flags", "model_role", "model_weight", "session_type", "vdot_eligibility", "harder_than_planned", "rpe", "perceived_intensity", "plan_compliance", "steady_min", "efficiency_m_min_per_bpm", "decoupling_pct"]
    public static let computedDailyColumns = ["health_score", "recovery_score", "nap_h", "sleep_flags", "main_sleep_attributed_h", "naps_attributed_h", "recovery_mean", "recovery_hrv", "recovery_rhr", "recovery_sleep", "recovery_load", "recovery_warnings"]

    /// Identificador corto y estable para auditar duplicados sin exponer el
    /// identificador interno de Salud (FNV-1a de 32 bits del UUID).
    public static func recordID(_ id: UUID) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in id.uuidString.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }

    /// Datos calculados que acompañan a un entrenamiento en la exportación.
    public struct WorkoutExtra: Hashable, Sendable {
        public var intensity: String
        public var intensityBasis: String
        public var qualityFlags: [String]
        /// counted, below_estimate, duplicate, inconsistent o vacío si no es una prueba.
        public var modelRole: String
        public var modelWeight: Double?
        /// Tipo de sesión (plan o estructura): easy, long, tempo, intervals…
        public var sessionType: String
        /// confirmed, candidate o not_eligible:<motivo>.
        public var vdotEligibility: String
        /// Sesión suave del plan hecha con intensidad alta.
        public var harderThanPlanned = false
        /// Esfuerzo percibido 1–10 que anotaste.
        public var rpe: Int?
        /// Intensidad percibida según tu RPE (Borg CR-10).
        public var perceivedIntensity = ""
        /// as_planned, harder, easier o vacío.
        public var planCompliance = ""
        /// Análisis aeróbico (formato 5): minutos de tramos estables, eficiencia y desacople.
        public var steadyMinutes: Double?
        public var efficiency: Double?
        public var decoupling: Double?

        public init(intensity: String = "", intensityBasis: String = "", qualityFlags: [String] = [], modelRole: String = "", modelWeight: Double? = nil, sessionType: String = "", vdotEligibility: String = "") {
            self.intensity = intensity
            self.intensityBasis = intensityBasis
            self.qualityFlags = qualityFlags
            self.modelRole = modelRole
            self.modelWeight = modelWeight
            self.sessionType = sessionType
            self.vdotEligibility = vdotEligibility
        }
    }

    public static func code(_ intensity: IntensityClass) -> String {
        switch intensity {
        case .unknown: ""
        case .recovery: "recovery"
        case .easy: "easy"
        case .moderate: "moderate"
        case .tempo: "tempo"
        case .intervals: "intervals"
        case .veryHard: "very_hard"
        case .test: "test"
        case .race: "race"
        }
    }

    public static func code(_ flag: WorkoutQualityFlag) -> String {
        switch flag {
        case .duplicate: "duplicate"
        case .overlaps: "overlaps"
        case .missingDistance: "missing_distance"
        case .tooShort: "too_short"
        case .implausiblePace: "implausible_pace"
        case .implausibleHeartRate: "implausible_hr"
        case .zeroCadence: "zero_cadence"
        case .implausibleCadence: "implausible_cadence"
        }
    }

    public static func code(_ eligibility: VDOTEligibility) -> String {
        switch eligibility {
        case .confirmed: "confirmed"
        case .candidate: "candidate"
        case let .notEligible(reason): "not_eligible:" + reason.rawValue  // nolocalize
        }
    }

    public static func code(_ flag: SleepNightFlag) -> String {
        switch flag {
        case .napIncluded: "nap_included"
        case .multipleSources: "multiple_sources"
        case .shortRecord: "short_record"
        case .fragmented: "fragmented"
        }
    }

    public static func code(_ role: PerformanceEvidence.Role) -> String {
        switch role {
        case .counted: "counted"
        case .belowEstimate: "unconfirmed_below_estimate"
        case .notMaximal: "not_maximal"
        case .duplicate: "duplicate"
        case .inconsistent: "inconsistent"
        }
    }

    /// Métricas diarias que se exportan, en orden de columna.
    public static let dailyKinds: [MetricKind] = [
        .restingHeartRate, .heartRateVariability, .respiratoryRate, .vo2Max, .oxygenSaturation,
        .steps, .walkingRunningDistance, .activeEnergy, .exerciseTime, .sleepDuration,
        .bodyMass, .bodyFatPercentage, .leanBodyMass, .wristTemperature, .timeInDaylight,
    ]

    public static func column(_ kind: MetricKind) -> String {
        switch kind {
        case .heartRate: "heart_rate_bpm"
        case .restingHeartRate: "resting_hr_bpm"
        case .heartRateVariability: "hrv_sdnn_ms"
        case .respiratoryRate: "respiratory_rate_per_min"
        case .vo2Max: "vo2max_ml_kg_min"
        case .oxygenSaturation: "spo2_pct"
        case .steps: "steps"
        case .walkingRunningDistance: "walk_run_distance_km"
        case .activeEnergy: "active_energy_kcal"
        case .exerciseTime: "exercise_min"
        case .sleepDuration: "sleep_h"
        case .bodyMass: "weight_kg"
        case .bodyFatPercentage: "body_fat_pct"
        case .leanBodyMass: "lean_mass_kg"
        case .wristTemperature: "wrist_temp_c"
        case .timeInDaylight: "daylight_min"
        }
    }

    /// Valor en la unidad de la columna (Salud guarda SpO₂ y grasa como fracción y la distancia en metros).
    static func exported(_ kind: MetricKind, _ value: Double) -> Double {
        switch kind {
        case .oxygenSaturation, .bodyFatPercentage: value <= 1.5 ? value * 100 : value
        case .walkingRunningDistance: value / 1000
        default: value
        }
    }

    static func digits(_ kind: MetricKind) -> Int {
        switch kind {
        case .steps, .activeEnergy, .exerciseTime, .timeInDaylight, .restingHeartRate: 0
        case .walkingRunningDistance, .sleepDuration, .wristTemperature: 2
        default: 1
        }
    }

    // MARK: Diario

    /// Una fila por día (de más antiguo a más nuevo), con las puntuaciones de
    /// HÅLSYN y los detalles del sueño. Celdas vacías = sin dato.
    /// - `recovery`: estimaciones completas para las columnas de factores (formato 4).
    /// - `attribution`: sueño atribuido por día (principal al despertar, siestas al empezar).
    public static func dailyCSV(series: [MetricSeries], healthScores: [DailyScore], recoveryScores: [Date: Int], sleep: [SleepNight], days: [Date], recovery estimates: [Date: RecoveryEstimate] = [:], attribution: [Date: SleepAttribution.Day] = [:], calendar: Calendar) -> String {
        var header = ["date"] + dailyKinds.map(column)
        header += ["sleep_start", "sleep_end", "sleep_deep_h", "sleep_rem_h", "sleep_core_h", "sleep_awake_h", "health_score", "recovery_score", "nap_h", "sleep_flags"]
        header += ["main_sleep_attributed_h", "naps_attributed_h", "recovery_mean", "recovery_hrv", "recovery_rhr", "recovery_sleep", "recovery_load", "recovery_warnings"]
        let estimatesByDay = Dictionary(estimates.map { (calendar.startOfDay(for: $0.key), $0.value) }, uniquingKeysWith: { $1 })
        let attributed = Dictionary(attribution.map { (calendar.startOfDay(for: $0.key), $0.value) }, uniquingKeysWith: { $1 })
        var rows = [header.joined(separator: ",")]

        func key(_ date: Date) -> Date { calendar.startOfDay(for: date) }
        var byKind: [MetricKind: [Date: Double]] = [:]
        for item in series {
            byKind[item.kind] = Dictionary(item.values.map { (key($0.day), $0.value) }, uniquingKeysWith: { $1 })
        }
        let health = Dictionary(healthScores.map { (key($0.day), $0.value) }, uniquingKeysWith: { $1 })
        let recovery = Dictionary(recoveryScores.map { (key($0.key), $0.value) }, uniquingKeysWith: { $1 })
        let nights = Dictionary(sleep.map { (key($0.day), $0) }, uniquingKeysWith: { $1 })

        for day in days.map(key).sorted() {
            var cells = [isoDate(day, calendar: calendar)]
            for kind in dailyKinds {
                cells.append(byKind[kind]?[day].map { number(exported(kind, $0), digits: digits(kind)) } ?? "")
            }
            if let night = nights[day] {
                cells.append(isoDateTime(night.sleepStart, calendar: calendar))
                cells.append(isoDateTime(night.sleepEnd, calendar: calendar))
                for stage in [SleepSample.Stage.asleepDeep, .asleepREM, .asleepCore] {
                    cells.append(night.stages[stage].map { number($0 / 3600, digits: 2) } ?? "")
                }
                cells.append(number(night.awake / 3600, digits: 2))
            } else {
                cells += ["", "", "", "", "", ""]
            }
            cells.append(health[day].map(String.init) ?? "")
            cells.append(recovery[day].map(String.init) ?? "")
            cells.append(nights[day].map { number($0.napAsleep / 3600, digits: 2) } ?? "")
            cells.append(nights[day].map { $0.flags.map(code).joined(separator: "|") } ?? "")
            cells.append(attributed[day].map { number($0.main / 3600, digits: 2) } ?? "")
            cells.append(attributed[day].map { number($0.naps / 3600, digits: 2) } ?? "")
            let estimate = estimatesByDay[day]
            cells.append(estimate?.weightedMean.map { number($0, digits: 1) } ?? "")
            for kind in [RecoveryComponentKind.heartRateVariability, .restingHeartRate, .sleep, .recentLoad] {
                cells.append(estimate?.components.first { $0.kind == kind }?.score.map(String.init) ?? "")
            }
            cells.append(estimate?.warnings.map(code).joined(separator: "|") ?? "")
            rows.append(cells.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: Entrenamientos

    public static let workoutHeader = [
        "date", "start_time", "type", "distance_km", "duration_min", "pace_min_km", "pace_s_per_km",
        "avg_hr_bpm", "max_hr_bpm", "cadence_spm", "active_energy_kcal", "elevation_gain_m",
        "avg_power_w", "temperature_c", "humidity_pct", "marked_as", "shoe",
        "record_id", "source", "intensity", "intensity_basis", "quality_flags", "model_role", "model_weight",
        "session_type", "vdot_eligibility", "harder_than_planned",
        "rpe", "perceived_intensity", "plan_compliance",
        "stride_length_m", "ground_contact_ms", "vertical_oscillation_cm", "running_power_w",
        "steady_min", "efficiency_m_min_per_bpm", "decoupling_pct",
    ]

    /// Una fila por entrenamiento, del más antiguo al más nuevo.
    /// `marks`: id del entrenamiento → "test" o "race"; `shoes`: id → nombre de la zapatilla.
    /// `extras`: datos calculados por HÅLSYN (intensidad, calidad, papel en el modelo).
    /// Un pulso de 0 se exporta vacío (es un dato ausente, no un valor).
    public static func workoutsCSV(_ workouts: [WorkoutSummary], marks: [UUID: String] = [:], shoes: [UUID: String] = [:], extras: [UUID: WorkoutExtra] = [:], calendar: Calendar) -> String {
        var rows = [workoutHeader.joined(separator: ",")]
        for workout in workouts.sorted(by: { $0.start < $1.start }) {
            let pace = workout.averagePace?.secondsPerKilometer
            let cells: [String] = [
                isoDate(workout.start, calendar: calendar),
                time(workout.start, calendar: calendar),
                type(workout.activity),
                workout.distanceMeters.map { number($0 / 1000, digits: 3) } ?? "",
                number(workout.duration / 60, digits: 2),
                pace.map { Pace(secondsPerKilometer: $0).formatted() } ?? "",
                pace.map { number($0, digits: 0) } ?? "",
                workout.averageHeartRate.flatMap { $0 > 0 ? number($0, digits: 0) : nil } ?? "",
                workout.maxHeartRate.flatMap { $0 > 0 ? number($0, digits: 0) : nil } ?? "",
                workout.averageCadence.map { number($0, digits: 0) } ?? "",
                workout.activeEnergyKilocalories.map { number($0, digits: 0) } ?? "",
                workout.elevationGain.map { number($0, digits: 0) } ?? "",
                workout.averagePower.map { number($0, digits: 0) } ?? "",
                workout.weather.map { number($0.temperature, digits: 1) } ?? "",
                workout.weather?.humidity.map { number($0 * 100, digits: 0) } ?? "",
                marks[workout.id] ?? "",
                escape(shoes[workout.id] ?? ""),
                recordID(workout.id),
                escape(source(workout.origin)),
                extras[workout.id]?.intensity ?? "",
                extras[workout.id]?.intensityBasis ?? "",
                extras[workout.id]?.qualityFlags.joined(separator: "|") ?? "",
                extras[workout.id]?.modelRole ?? "",
                extras[workout.id]?.modelWeight.map { number($0, digits: 3) } ?? "",
                extras[workout.id]?.sessionType ?? "",
                extras[workout.id]?.vdotEligibility ?? "",
                extras[workout.id]?.harderThanPlanned == true ? "yes" : "",
                extras[workout.id]?.rpe.map(String.init) ?? "",
                extras[workout.id]?.perceivedIntensity ?? "",
                extras[workout.id]?.planCompliance ?? "",
                workout.dynamics?.strideLength.map { number($0, digits: 2) } ?? "",
                workout.dynamics?.groundContactTime.map { number($0, digits: 0) } ?? "",
                workout.dynamics?.verticalOscillation.map { number($0, digits: 1) } ?? "",
                workout.dynamics?.power.map { number($0, digits: 0) } ?? "",
                extras[workout.id]?.steadyMinutes.map { number($0, digits: 1) } ?? "",
                extras[workout.id]?.efficiency.map { number($0, digits: 3) } ?? "",
                extras[workout.id]?.decoupling.map { number($0, digits: 1) } ?? "",
            ]
            rows.append(cells.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func source(_ origin: DataOrigin) -> String {
        switch origin {
        case .demo: "demo"
        case let .healthKit(name): name ?? "Apple Health"
        case let .derived(engine): "halsyn:" + engine  // nolocalize
        }
    }

    public static func code(_ warning: RecoveryWarning) -> String {
        switch warning {
        case .hrvUnusuallyHigh: "hrv_unusually_high"
        case .illness: "illness"
        case let .recentHardSession(hours): "hard_session_\(hours)h"  // nolocalize
        case .incompleteSleep: "incomplete_sleep"
        case .shortHRVWindow: "short_hrv_window"
        case .usesYesterday: "uses_yesterday"
        }
    }

    /// Motivo por el que un pico de FC no fija la máxima validada.
    public static func peakReason(_ status: MaxHeartRatePeak.Status) -> String {
        switch status {
        case .supported: "repetido en otra sesión"
        case .isolated: "pico aislado, no se repite en otra sesión"
        case .transient: "no se sostiene 15 s en las muestras"
        case .implausibleGap: "muy por encima de la FC media de la sesión"
        case .old: "de hace más de 12 meses"
        case .below: "por debajo de la validada"
        }
    }

    // MARK: Sueño por episodios

    /// Un episodio por fila con su hora real y el día al que se atribuye.
    public static func sleepEpisodesCSV(_ days: [Date: SleepAttribution.Day], calendar: Calendar) -> String {
        var rows = ["start,end,asleep_h,type,attributed_date"]  // nolocalize
        let episodes = days.values.flatMap(\.episodes).sorted { $0.start < $1.start }
        for episode in episodes {
            rows.append([
                isoDateTime(episode.start, calendar: calendar),
                isoDateTime(episode.end, calendar: calendar),
                number(episode.asleep / 3600, digits: 2),
                episode.isMain ? "main" : "nap",
                isoDate(episode.attributedDay(calendar: calendar), calendar: calendar),
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: Pruebas, eventos y laboratorio

    /// Pruebas del modelo de rendimiento con su peso y sus factores.
    public static func evidenceCSV(_ assessment: PerformanceAssessment, results: [PerformanceResult] = [], calendar: Calendar) -> String {
        let byID = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rows = ["date,kind,distance_km,time_s,vdot,role,weight,factor_kind,factor_age,factor_distance,factor_quality,factor_cap,factor_consistency,value_used,record_id,workout_record_id,duplicate_of"]  // nolocalize
        for item in assessment.evidence.sorted(by: { $0.date < $1.date }) {
            let kind: String
            switch item.kind {
            case .race: kind = "race"
            case .test: kind = "test"
            case .trainingEffort: kind = "training_effort"
            }
            let f = item.factors
            var duplicateOfText = ""
            if case let .duplicate(of: kept) = item.role { duplicateOfText = recordID(kept) }
            let workoutText: String = item.kind == .trainingEffort ? recordID(item.id) : (byID[item.id]?.workoutID.map(recordID) ?? "")
            rows.append([
                isoDate(item.date, calendar: calendar), kind, number(item.distance / 1000, digits: 3), number(item.time, digits: 0),
                number(item.vdot, digits: 2), code(item.role), number(item.weight, digits: 3),
                f.map { number($0.kind, digits: 2) } ?? "", f.map { number($0.age, digits: 3) } ?? "",
                f.map { number($0.distance, digits: 2) } ?? "", f.map { number($0.quality, digits: 2) } ?? "",
                f.map { number($0.cap, digits: 3) } ?? "", f.map { number($0.consistency, digits: 2) } ?? "",
                item.valueUsed.map { number($0, digits: 2) } ?? "", recordID(item.id),
                workoutText,
                duplicateOfText,
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// Todos los tests y competiciones registrados (también los duplicados), con
    /// su origen y a cuál duplican: trazabilidad completa entre el resumen, las
    /// pruebas del modelo y los entrenamientos (`workout_record_id` = `record_id`
    /// del entrenamiento en el CSV de entrenamientos).
    public static func resultsCSV(_ results: [PerformanceResult], distinct: Set<UUID> = [], calendar: Calendar) -> String {
        let duplicates = RacePerformanceModel.deduplicated(results, distinct: distinct, calendar: calendar).duplicates
        let duplicateOf = Dictionary(duplicates.map { ($0.0.id, $0.keptID) }, uniquingKeysWith: { first, _ in first })
        var rows = ["date,kind,distance_km,time_s,vdot,origin,record_id,workout_record_id,status,duplicate_of,marked_distinct"]  // nolocalize
        for result in results.sorted(by: { $0.date < $1.date }) {
            let status = duplicateOf[result.id] == nil ? "used" : "duplicate"
            rows.append([
                isoDate(result.date, calendar: calendar), result.kind.rawValue, number(result.distance / 1000, digits: 3), number(result.time, digits: 0),
                result.vdot.map { number($0, digits: 2) } ?? "", result.workoutID == nil ? "manual" : "workout",
                recordID(result.id), result.workoutID.map(recordID) ?? "", status,
                duplicateOf[result.id].map(recordID) ?? "", distinct.contains(result.id) ? "yes" : "",
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func healthEventsCSV(_ events: [HealthEvent], calendar: Calendar) -> String {
        var rows = ["start,end,kind,title,note"]  // nolocalize
        for event in events.sorted(by: { $0.start < $1.start }) {
            rows.append([isoDate(event.start, calendar: calendar), event.end.map { isoDate($0, calendar: calendar) } ?? "", event.kind.rawValue, escape(event.title), escape(event.note ?? "")].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func labResultsCSV(_ results: [LabResult], calendar: Calendar) -> String {
        var rows = ["date,kind,name,value,unit,reference,reference_source,note"]  // nolocalize
        for result in results.sorted(by: { $0.date < $1.date }) {
            let reference = LabReference.general(result.kind)
            rows.append([
                isoDate(result.date, calendar: calendar), result.kind.rawValue, escape(result.customName ?? ""),
                number(result.value, digits: 2), escape(result.unit), escape(reference?.summary ?? ""), escape(reference?.source ?? ""), escape(result.note ?? ""),
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// Resumen de calidad: cuántos entrenamientos tienen cada aviso.
    public static func qualitySummary(_ workouts: [WorkoutSummary]) -> [(code: String, count: Int)] {
        var counts: [String: Int] = [:]
        for quality in DataQuality.assess(workouts).values {
            for flag in Set(quality.flags.map(code)) { counts[flag, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map { ($0.key, $0.value) }
    }

    static func type(_ activity: WorkoutActivity) -> String {
        switch activity {
        case .outdoorRun: "run_outdoor"
        case .indoorRun: "run_treadmill"
        case .walk: "walk"
        case .outdoorRide: "ride_outdoor"
        case .indoorRide: "ride_indoor"
        case .other: "other"
        }
    }

    // MARK: Formato

    static let posix = Locale(identifier: "en_US_POSIX")

    public static func number(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%.\(digits)f", locale: posix, value)
    }

    static func isoDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func time(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func isoDateTime(_ date: Date, calendar: Calendar) -> String {
        "\(isoDate(date, calendar: calendar)) \(time(date, calendar: calendar))"
    }

    /// Texto entre comillas si tiene comas, comillas o saltos de línea.
    public static func escape(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
