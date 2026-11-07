import Foundation

/// Exportación de datos crudos en CSV (para hojas de cálculo o para pegar en
/// una IA). Columnas en inglés con la unidad en el nombre, punto decimal y
/// fechas ISO, para que cualquier herramienta las lea sin ambigüedad.
public enum DataExport {
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
    public static func dailyCSV(series: [MetricSeries], healthScores: [DailyScore], recoveryScores: [Date: Int], sleep: [SleepNight], days: [Date], calendar: Calendar) -> String {
        var header = ["date"] + dailyKinds.map(column)
        header += ["sleep_start", "sleep_end", "sleep_deep_h", "sleep_rem_h", "sleep_core_h", "sleep_awake_h", "health_score", "recovery_score"]
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
            rows.append(cells.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: Entrenamientos

    public static let workoutHeader = [
        "date", "start_time", "type", "distance_km", "duration_min", "pace_min_km", "pace_s_per_km",
        "avg_hr_bpm", "max_hr_bpm", "cadence_spm", "active_energy_kcal", "elevation_gain_m",
        "avg_power_w", "temperature_c", "humidity_pct", "marked_as", "shoe",
    ]

    /// Una fila por entrenamiento, del más antiguo al más nuevo.
    /// `marks`: id del entrenamiento → "test" o "race"; `shoes`: id → nombre de la zapatilla.
    public static func workoutsCSV(_ workouts: [WorkoutSummary], marks: [UUID: String] = [:], shoes: [UUID: String] = [:], calendar: Calendar) -> String {
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
                workout.averageHeartRate.map { number($0, digits: 0) } ?? "",
                workout.maxHeartRate.map { number($0, digits: 0) } ?? "",
                workout.averageCadence.map { number($0, digits: 0) } ?? "",
                workout.activeEnergyKilocalories.map { number($0, digits: 0) } ?? "",
                workout.elevationGain.map { number($0, digits: 0) } ?? "",
                workout.averagePower.map { number($0, digits: 0) } ?? "",
                workout.weather.map { number($0.temperature, digits: 1) } ?? "",
                workout.weather?.humidity.map { number($0 * 100, digits: 0) } ?? "",
                marks[workout.id] ?? "",
                escape(shoes[workout.id] ?? ""),
            ]
            rows.append(cells.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
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
