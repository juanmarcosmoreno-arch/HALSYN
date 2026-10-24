import Foundation

/// Componentes de Life's Essential 8 (American Heart Association, 2022).
public enum CardioComponent: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case diet
    case physicalActivity
    case nicotine
    case sleep
    case bodyMassIndex
    case bloodLipids
    case bloodGlucose
    case bloodPressure

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .diet: "Alimentación"
        case .physicalActivity: "Actividad física"
        case .nicotine: "Nicotina"
        case .sleep: "Sueño"
        case .bodyMassIndex: "Peso (IMC)"
        case .bloodLipids: "Colesterol"
        case .bloodGlucose: "Glucosa"
        case .bloodPressure: "Presión arterial"
        }
    }

    public var systemImage: String {
        switch self {
        case .diet: "leaf"
        case .physicalActivity: "figure.walk"
        case .nicotine: "nosign"
        case .sleep: "moon.zzz"
        case .bodyMassIndex: "scalemass"
        case .bloodLipids: "drop"
        case .bloodGlucose: "drop.triangle"
        case .bloodPressure: "heart.text.square"
        }
    }

    /// `true` si sale solo de Apple Health; el resto lo escribe el usuario.
    public var isAutomatic: Bool {
        self == .physicalActivity || self == .sleep || self == .bodyMassIndex
    }
}

/// Consumo de nicotina, con las categorías de Life's Essential 8.
public enum NicotineStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case never
    case quitFiveYearsOrMore
    case quitOneToFiveYears
    case quitLessThanOneYear
    /// Vapeo o cigarrillo electrónico.
    case currentVaping
    case currentSmoking

    public var title: String {
        switch self {
        case .never: "Nunca fumé"
        case .quitFiveYearsOrMore: "Lo dejé hace 5 años o más"
        case .quitOneToFiveYears: "Lo dejé hace 1 a 5 años"
        case .quitLessThanOneYear: "Lo dejé hace menos de 1 año"
        case .currentVaping: "Vapeo o cigarrillo electrónico"
        case .currentSmoking: "Fumo"
        }
    }
}

/// Lo que la persona escribe a mano: análisis, presión y hábitos.
public struct CardioHealthInputs: Codable, Hashable, Sendable {
    public struct BloodPressure: Codable, Hashable, Sendable {
        public var systolic: Double
        public var diastolic: Double
        public var treated: Bool
        public var date: Date
        public init(systolic: Double, diastolic: Double, treated: Bool, date: Date) {
            self.systolic = systolic
            self.diastolic = diastolic
            self.treated = treated
            self.date = date
        }
    }

    public struct Lipids: Codable, Hashable, Sendable {
        /// Colesterol total y HDL en mg/dL.
        public var totalCholesterol: Double
        public var hdl: Double
        public var treated: Bool
        public var date: Date
        public init(totalCholesterol: Double, hdl: Double, treated: Bool, date: Date) {
            self.totalCholesterol = totalCholesterol
            self.hdl = hdl
            self.treated = treated
            self.date = date
        }
        /// Colesterol no-HDL (total − HDL), el que usa Life's Essential 8.
        public var nonHDL: Double { totalCholesterol - hdl }
    }

    public struct Glucose: Codable, Hashable, Sendable {
        public var hasDiabetes: Bool
        /// Glucosa en ayunas (mg/dL), si se conoce.
        public var fastingGlucose: Double?
        /// HbA1c (%), si se conoce.
        public var hbA1c: Double?
        public var date: Date
        public init(hasDiabetes: Bool, fastingGlucose: Double?, hbA1c: Double?, date: Date) {
            self.hasDiabetes = hasDiabetes
            self.fastingGlucose = fastingGlucose
            self.hbA1c = hbA1c
            self.date = date
        }
    }

    public struct Nicotine: Codable, Hashable, Sendable {
        public var status: NicotineStatus
        /// Alguien fuma dentro de casa.
        public var secondhandAtHome: Bool
        public init(status: NicotineStatus, secondhandAtHome: Bool) {
            self.status = status
            self.secondhandAtHome = secondhandAtHome
        }
    }

    public var bloodPressure: BloodPressure?
    public var lipids: Lipids?
    public var glucose: Glucose?
    public var nicotine: Nicotine?

    public init(bloodPressure: BloodPressure? = nil, lipids: Lipids? = nil, glucose: Glucose? = nil, nicotine: Nicotine? = nil) {
        self.bloodPressure = bloodPressure
        self.lipids = lipids
        self.glucose = glucose
        self.nicotine = nicotine
    }
}

/// Datos medidos que entran al cálculo.
public struct CardioHealthMeasurements: Hashable, Sendable {
    /// Minutos de ejercicio de los últimos 7 días (Apple: actividad moderada o más).
    public var weeklyActivityMinutes: Double?
    /// Media de horas dormidas por noche.
    public var averageSleepHours: Double?
    public var bodyMassIndex: Double?

    public init(weeklyActivityMinutes: Double? = nil, averageSleepHours: Double? = nil, bodyMassIndex: Double? = nil) {
        self.weeklyActivityMinutes = weeklyActivityMinutes
        self.averageSleepHours = averageSleepHours
        self.bodyMassIndex = bodyMassIndex
    }
}

public struct CardioComponentScore: Hashable, Identifiable, Sendable {
    public let component: CardioComponent
    /// 0–100; `nil` si falta el dato.
    public let points: Int?
    public var id: CardioComponent { component }
}

/// Nivel de salud cardiovascular según la AHA.
public enum CardioHealthLevel: String, Sendable {
    case high
    case moderate
    case low

    public init(score: Int) {
        switch score {
        case 80...: self = .high
        case 50..<80: self = .moderate
        default: self = .low
        }
    }

    public var title: String {
        switch self {
        case .high: "Salud cardiovascular alta"
        case .moderate: "Salud cardiovascular moderada"
        case .low: "Salud cardiovascular baja"
        }
    }
}

public struct CardioHealthResult: Hashable, Sendable {
    public let components: [CardioComponentScore]
    /// Media simple de los componentes con dato; `nil` con menos de `minimumComponents`.
    public let score: Int?
    public var available: [CardioComponentScore] { components.filter { $0.points != nil } }
    public var isComplete: Bool { available.count == CardioComponent.allCases.count }
    public var level: CardioHealthLevel? { score.map(CardioHealthLevel.init(score:)) }
}

/// Life's Essential 8 (Lloyd-Jones et al., Circulation 2022): ocho componentes
/// de 0 a 100 y su media simple.
///
/// - Puntos de cada componente según las tablas publicadas para adultos.
/// - Actividad: minutos de ejercicio de Apple como aproximación a los minutos
///   de actividad moderada o vigorosa (la AHA cuenta doble los vigorosos).
/// - Alimentación: requiere un cuestionario validado (MEPA); aún no se calcula.
/// - Con componentes sin dato se promedia lo disponible y se indica.
public enum CardiovascularHealthEngine {
    public static let version = "LE8-2022"
    public static let minimumComponents = 4

    public static func evaluate(measurements: CardioHealthMeasurements, inputs: CardioHealthInputs) -> CardioHealthResult {
        let components = CardioComponent.allCases.map { component -> CardioComponentScore in
            let points: Int?
            switch component {
            case .diet: points = nil
            case .physicalActivity: points = measurements.weeklyActivityMinutes.map(activityPoints)
            case .nicotine: points = inputs.nicotine.map(nicotinePoints)
            case .sleep: points = measurements.averageSleepHours.map(sleepPoints)
            case .bodyMassIndex: points = measurements.bodyMassIndex.map(bodyMassIndexPoints)
            case .bloodLipids: points = inputs.lipids.map { lipidPoints(nonHDL: $0.nonHDL, treated: $0.treated) }
            case .bloodGlucose: points = inputs.glucose.flatMap(glucosePoints)
            case .bloodPressure: points = inputs.bloodPressure.map { bloodPressurePoints(systolic: $0.systolic, diastolic: $0.diastolic, treated: $0.treated) }
            }
            return CardioComponentScore(component: component, points: points)
        }
        let values = components.compactMap(\.points)
        let score = values.count >= minimumComponents ? Int((Double(values.reduce(0, +)) / Double(values.count)).rounded()) : nil
        return CardioHealthResult(components: components, score: score)
    }

    // MARK: Tablas (adultos)

    /// Minutos semanales de actividad moderada o vigorosa.
    public static func activityPoints(_ minutes: Double) -> Int {
        switch minutes {
        case 150...: 100
        case 120..<150: 90
        case 90..<120: 80
        case 60..<90: 60
        case 30..<60: 40
        case 1..<30: 20
        default: 0
        }
    }

    /// Horas medias de sueño por noche.
    public static func sleepPoints(_ hours: Double) -> Int {
        switch hours {
        case 7..<9: 100
        case 9..<10: 90
        case 6..<7: 70
        case 5..<6, 10...: 40
        case 4..<5: 20
        default: 0
        }
    }

    public static func bodyMassIndexPoints(_ bmi: Double) -> Int {
        switch bmi {
        case ..<25: 100
        case 25..<30: 70
        case 30..<35: 30
        case 35..<40: 15
        default: 0
        }
    }

    public static func nicotinePoints(_ nicotine: CardioHealthInputs.Nicotine) -> Int {
        let base: Int
        switch nicotine.status {
        case .never: base = 100
        case .quitFiveYearsOrMore: base = 75
        case .quitOneToFiveYears: base = 50
        case .quitLessThanOneYear, .currentVaping: base = 25
        case .currentSmoking: base = 0
        }
        // Humo ajeno en casa: −20 (sin bajar de 0).
        return nicotine.secondhandAtHome ? max(0, base - 20) : base
    }

    /// Colesterol no-HDL (mg/dL); −20 si está tratado con medicación.
    public static func lipidPoints(nonHDL: Double, treated: Bool) -> Int {
        let base: Int
        switch nonHDL {
        case ..<130: base = 100
        case 130..<160: base = 60
        case 160..<190: base = 40
        case 190..<220: base = 20
        default: base = 0
        }
        return treated ? max(0, base - 20) : base
    }

    /// Sin diabetes: glucosa en ayunas o HbA1c. Con diabetes: HbA1c.
    public static func glucosePoints(_ glucose: CardioHealthInputs.Glucose) -> Int? {
        if glucose.hasDiabetes {
            guard let a1c = glucose.hbA1c else { return nil }
            switch a1c {
            case ..<7: return 40
            case 7..<8: return 30
            case 8..<9: return 20
            case 9..<10: return 10
            default: return 0
            }
        }
        if let fasting = glucose.fastingGlucose {
            return fasting < 100 ? 100 : 60
        }
        if let a1c = glucose.hbA1c {
            return a1c < 5.7 ? 100 : 60
        }
        return nil
    }

    /// Presión en mmHg; −20 si está tratada con medicación.
    public static func bloodPressurePoints(systolic: Double, diastolic: Double, treated: Bool) -> Int {
        let base: Int
        if systolic >= 160 || diastolic >= 100 {
            base = 0
        } else if systolic >= 140 || diastolic >= 90 {
            base = 25
        } else if systolic >= 130 || diastolic >= 80 {
            base = 50
        } else if systolic >= 120 {
            base = 75
        } else {
            base = 100
        }
        return treated ? max(0, base - 20) : base
    }

    public static func bodyMassIndex(weightKilograms: Double, heightMeters: Double) -> Double? {
        guard heightMeters > 0.5, weightKilograms > 0 else { return nil }
        return weightKilograms / (heightMeters * heightMeters)
    }
}

extension HealthDataProviding {
    /// Mediciones de Apple Health para Life's Essential 8.
    public func cardioHealthMeasurements(on day: Date, heightMeters: Double?, calendar: Calendar) async -> CardioHealthMeasurements {
        let start = calendar.startOfDay(for: day)
        // Actividad: los 7 días completos anteriores (con al menos 4 registrados).
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let exercise = await dailySeries(.exerciseTime, days: 7, endingOn: yesterday).values
        let minutes = exercise.count >= 4 ? exercise.map(\.value).reduce(0, +) : nil
        // Sueño: media de las noches de las últimas 2 semanas (al menos 7).
        let sleep = await dailySeries(.sleepDuration, days: 14, endingOn: start).values
        let hours = sleep.count >= 7 ? sleep.map(\.value).reduce(0, +) / Double(sleep.count) : nil
        var bmi: Double?
        if let heightMeters, let weight = await latest(.bodyMass, on: start).reading?.value {
            bmi = CardiovascularHealthEngine.bodyMassIndex(weightKilograms: weight, heightMeters: heightMeters)
        }
        return CardioHealthMeasurements(weeklyActivityMinutes: minutes, averageSleepHours: hours, bodyMassIndex: bmi)
    }
}
