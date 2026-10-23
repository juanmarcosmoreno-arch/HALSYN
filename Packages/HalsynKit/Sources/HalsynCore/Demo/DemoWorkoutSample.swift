import Foundation

/// Valor ya formateado de un campo de entrenamiento.
public struct WorkoutFieldValue: Hashable, Sendable {
    public var value: String?
    public var unit: String

    public init(value: String?, unit: String) {
        self.value = value
        self.unit = unit
    }
}

/// Instantánea fija de una carrera, solo para vistas previas y modo demo.
/// Nunca se guarda en Apple Health.
public struct DemoWorkoutSample: Sendable {
    public var elapsed: TimeInterval = 24 * 60 + 36
    public var distanceMeters: Double = 5210
    public var currentPace = Pace(secondsPerKilometer: 279)
    public var heartRate: Double = 148
    public var heartRateZone = 3
    public var cadence: Double = 172
    public var lapElapsed: TimeInterval = 142
    public var targetPace = Pace(secondsPerKilometer: 285)
    public var intervalRemaining: TimeInterval = 95
    public var power: Double = 268
    public var elevationGain: Double = 46

    public init() {}

    public var averagePace: Pace? { Pace(distanceMeters: distanceMeters, duration: elapsed) }

    public func value(for field: WorkoutFieldKind, unit: UnitSystem = .metric) -> WorkoutFieldValue {
        switch field {
        case .elapsedTime: WorkoutFieldValue(value: HalsynFormat.duration(elapsed), unit: "")
        case .distance: WorkoutFieldValue(value: HalsynFormat.distance(meters: distanceMeters, unit: unit), unit: unit.distanceUnitSymbol)
        case .currentPace: WorkoutFieldValue(value: currentPace.formatted(in: unit), unit: unit.paceUnitSymbol)
        case .averagePace: WorkoutFieldValue(value: averagePace?.formatted(in: unit), unit: unit.paceUnitSymbol)
        case .heartRate: WorkoutFieldValue(value: String(Int(heartRate)), unit: "lpm")
        case .heartRateZone: WorkoutFieldValue(value: "Z\(heartRateZone)", unit: "")
        case .cadence: WorkoutFieldValue(value: String(Int(cadence)), unit: "ppm")
        case .lapTime: WorkoutFieldValue(value: HalsynFormat.duration(lapElapsed), unit: "")
        case .lapPace: WorkoutFieldValue(value: Pace(secondsPerKilometer: 281).formatted(in: unit), unit: unit.paceUnitSymbol)
        case .targetPace: WorkoutFieldValue(value: targetPace.formatted(in: unit), unit: unit.paceUnitSymbol)
        case .intervalTime: WorkoutFieldValue(value: HalsynFormat.duration(intervalRemaining), unit: "")
        case .runningPower: WorkoutFieldValue(value: String(Int(power)), unit: "W")
        case .elevationGain: WorkoutFieldValue(value: String(Int(elevationGain)), unit: "m")
        }
    }
}
