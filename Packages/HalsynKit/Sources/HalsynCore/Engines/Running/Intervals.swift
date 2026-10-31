import Foundation

/// Rango de ritmo objetivo, en segundos por kilómetro (`fastest` < `slowest`).
public struct PaceRange: Hashable, Codable, Sendable {
    public var fastest: Double
    public var slowest: Double

    public init(fastest: Double, slowest: Double) {
        self.fastest = min(fastest, slowest)
        self.slowest = max(fastest, slowest)
    }

    /// Rango centrado en un ritmo, ± `tolerance` segundos por kilómetro.
    public init(center: Pace, tolerance: Double = 5) {
        self.init(fastest: center.secondsPerKilometer - tolerance, slowest: center.secondsPerKilometer + tolerance)
    }

    public var center: Pace { Pace(secondsPerKilometer: (fastest + slowest) / 2) }

    /// "4:40–4:50" en la unidad elegida.
    public func formatted(in unit: UnitSystem = .metric) -> String {
        "\(Pace(secondsPerKilometer: fastest).formatted(in: unit))–\(Pace(secondsPerKilometer: slowest).formatted(in: unit))"
    }
}

/// Cuándo termina un paso de un entrenamiento por intervalos.
public enum IntervalGoal: Hashable, Codable, Sendable {
    case time(TimeInterval)
    case distance(Double)
    /// Termina al pulsar "Vuelta".
    case open
}

public enum IntervalStepKind: String, Hashable, Codable, CaseIterable, Sendable {
    case warmup, work, recovery, cooldown

    public var title: String {
        switch self {
        case .warmup: "Calentamiento"
        case .work: "Serie"
        case .recovery: "Recuperación"
        case .cooldown: "Vuelta a la calma"
        }
    }

    /// Etiqueta corta para el reloj.
    public var label: String {
        switch self {
        case .warmup: "CALENTAR"
        case .work: "SERIE"
        case .recovery: "RECUPERAR"
        case .cooldown: "CALMA"
        }
    }
}

/// Tipo de entrenamiento armado: cambia los nombres de los pasos en el reloj,
/// la voz y la plantilla con la que empieza. La estructura es la misma
/// (calentamiento, bloques con recuperación, vuelta a la calma).
public enum WorkoutStyle: String, Hashable, Codable, CaseIterable, Sendable {
    /// Series por distancia o tiempo con recuperación.
    case intervals
    /// Subidas cortas y fuertes; se baja trotando.
    case hills
    /// Cambios de ritmo por tiempo, sin parar.
    case fartlek
    /// Un bloque largo y continuo.
    case long

    public var title: String {
        switch self {
        case .intervals: "Pasadas"
        case .hills: "Repechos"
        case .fartlek: "Fartlek"
        case .long: "Fondo"
        }
    }

    public var symbol: String {
        switch self {
        case .intervals: "repeat"
        case .hills: "mountain.2"
        case .fartlek: "waveform.path"
        case .long: "road.lanes"
        }
    }

    /// Nombre del paso para la pantalla y los avisos.
    public func title(for kind: IntervalStepKind) -> String {
        switch (self, kind) {
        case (.hills, .work): "Repecho"
        case (.hills, .recovery): "Bajada"
        case (.fartlek, .work): "Rápido"
        case (.fartlek, .recovery): "Suave"
        case (.long, .work): "Fondo"
        default: kind.title
        }
    }

    /// Etiqueta corta del paso en el reloj.
    public func label(for kind: IntervalStepKind) -> String {
        switch (self, kind) {
        case (.hills, .work): "SUBIDA"
        case (.hills, .recovery): "BAJADA"
        case (.fartlek, .work): "RÁPIDO"
        case (.fartlek, .recovery): "SUAVE"
        case (.long, .work): "FONDO"
        default: kind.label
        }
    }

    /// Plantilla para un entrenamiento nuevo de este tipo (todo se puede editar).
    public func template(id: String, name: String) -> IntervalPlan {
        switch self {
        case .intervals:
            IntervalPlan(id: id, name: name, warmup: .time(600), work: .distance(400), recovery: .time(90), repeats: 8, cooldown: .time(300), style: .intervals)
        case .hills:
            // Subidas de 30–60 s a esfuerzo fuerte; la bajada al trote es la recuperación.
            IntervalPlan(id: id, name: name, warmup: .time(900), work: .time(45), recovery: .time(90), repeats: 8, cooldown: .time(300), style: .hills)
        case .fartlek:
            IntervalPlan(id: id, name: name, warmup: .time(600), work: .time(60), recovery: .time(60), repeats: 10, cooldown: .time(300), style: .fartlek)
        case .long:
            IntervalPlan(id: id, name: name, warmup: nil, work: .distance(15_000), recovery: .open, repeats: 1, cooldown: nil, style: .long)
        }
    }
}

public struct IntervalStep: Hashable, Codable, Sendable {
    public var kind: IntervalStepKind
    public var goal: IntervalGoal
    /// Ritmo objetivo (solo para las series). Activa las alertas de ritmo del paso.
    public var paceTarget: PaceRange?
    /// Número de repetición (1…n) en series y recuperaciones.
    public var repetition: Int?

    public init(kind: IntervalStepKind, goal: IntervalGoal, paceTarget: PaceRange? = nil, repetition: Int? = nil) {
        self.kind = kind
        self.goal = goal
        self.paceTarget = paceTarget
        self.repetition = repetition
    }
}

/// Plan de intervalos: calentamiento, `repeats` × (serie + recuperación), vuelta a la calma.
/// La última recuperación se omite: tras la última serie se pasa a la calma.
public struct IntervalPlan: Hashable, Codable, Identifiable, Sendable {
    public static let repeatsRange: ClosedRange<Int> = 1...30

    public var id: String
    public var name: String
    public var warmup: IntervalGoal?
    public var work: IntervalGoal
    public var workPace: PaceRange?
    public var recovery: IntervalGoal
    public var repeats: Int
    public var cooldown: IntervalGoal?
    /// Tipo (pasadas, repechos, fartlek, fondo). `nil` en los guardados antes = pasadas.
    public var style: WorkoutStyle?

    public init(id: String, name: String, warmup: IntervalGoal?, work: IntervalGoal, workPace: PaceRange? = nil, recovery: IntervalGoal, repeats: Int, cooldown: IntervalGoal?, style: WorkoutStyle? = nil) {
        self.id = id
        self.name = name
        self.warmup = warmup
        self.work = work
        self.workPace = workPace
        self.recovery = recovery
        self.repeats = min(max(repeats, Self.repeatsRange.lowerBound), Self.repeatsRange.upperBound)
        self.cooldown = cooldown
        self.style = style
    }

    public var kind: WorkoutStyle { style ?? .intervals }

    public var steps: [IntervalStep] {
        var steps: [IntervalStep] = []
        if let warmup { steps.append(IntervalStep(kind: .warmup, goal: warmup)) }
        for repetition in 1...max(repeats, 1) {
            steps.append(IntervalStep(kind: .work, goal: work, paceTarget: workPace, repetition: repetition))
            if repetition < repeats {
                steps.append(IntervalStep(kind: .recovery, goal: recovery, repetition: repetition))
            }
        }
        if let cooldown { steps.append(IntervalStep(kind: .cooldown, goal: cooldown)) }
        return steps
    }

    public static let presets: [IntervalPlan] = [
        IntervalPlan(id: "6x400", name: "6 × 400 m", warmup: .time(600), work: .distance(400), recovery: .time(90), repeats: 6, cooldown: .time(300)),
        IntervalPlan(id: "5x1k", name: "5 × 1 km", warmup: .time(600), work: .distance(1000), recovery: .time(120), repeats: 5, cooldown: .time(300)),
        IntervalPlan(id: "8x1min", name: "8 × 1 min", warmup: .time(600), work: .time(60), recovery: .time(60), repeats: 8, cooldown: .time(300)),
        WorkoutStyle.hills.template(id: "hills-8x45", name: "Repechos 8 × 45 s"),
        WorkoutStyle.fartlek.template(id: "fartlek-10x1", name: "Fartlek 10 × 1 min"),
        WorkoutStyle.long.template(id: "long-15k", name: "Fondo 15 km"),
    ]
}

/// Cómo se reparte un plan en el reloj: el calentamiento va antes y no se graba
/// (ni tiempo ni distancia); la vuelta a la calma, si se mide la recuperación,
/// va después y es esa medición. El resto es el entrenamiento que se guarda.
public struct IntervalSessionLayout: Hashable, Sendable {
    /// Calentamiento previo, fuera del entrenamiento (`nil` = no hay).
    public let warmup: IntervalGoal?
    /// Lo que se graba: el plan sin el calentamiento (y sin la calma si se mide).
    public let recorded: IntervalPlan
    /// Minutos de la medición de recuperación que reemplaza a la calma
    /// (`nil` = la calma queda dentro del entrenamiento, como antes).
    public let recoveryMinutes: Int?

    /// Una medición más larga no aporta (se miden 1, 2 y 5 minutos).
    public static let recoveryMinuteRange: ClosedRange<Int> = 1...10

    public init(plan: IntervalPlan, measuresRecovery: Bool, defaultRecoveryMinutes: Int) {
        var recorded = plan
        warmup = plan.warmup
        recorded.warmup = nil
        if measuresRecovery, let cooldown = plan.cooldown {
            recorded.cooldown = nil
            recoveryMinutes = Self.minutes(for: cooldown, default: defaultRecoveryMinutes)
        } else {
            recoveryMinutes = nil
        }
        self.recorded = recorded
    }

    /// Una calma por tiempo dura lo mismo; por distancia o abierta, lo elegido en Ajustes.
    static func minutes(for cooldown: IntervalGoal, default fallback: Int) -> Int {
        let range = recoveryMinuteRange
        if case let .time(seconds) = cooldown {
            return min(max(Int((seconds / 60).rounded()), range.lowerBound), range.upperBound)
        }
        return min(max(fallback, range.lowerBound), range.upperBound)
    }
}

/// Progreso del paso actual.
public struct IntervalProgress: Hashable, Sendable {
    public var step: IntervalStep
    public var index: Int
    public var count: Int
    public var elapsed: TimeInterval
    public var distance: Double

    /// Lo que falta del objetivo del paso (segundos o metros); `nil` en pasos abiertos.
    public var remaining: Double? {
        switch step.goal {
        case let .time(target): max(0, target - elapsed)
        case let .distance(target): max(0, target - distance)
        case .open: nil
        }
    }

    /// 0…1, o `nil` en pasos abiertos.
    public var fraction: Double? {
        switch step.goal {
        case let .time(target): target > 0 ? min(elapsed / target, 1) : 1
        case let .distance(target): target > 0 ? min(distance / target, 1) : 1
        case .open: nil
        }
    }
}

/// Avanza por los pasos de un `IntervalPlan` con el tiempo activo y la distancia.
public struct IntervalTracker: Sendable {
    public let plan: IntervalPlan
    public let steps: [IntervalStep]
    public private(set) var index = 0
    private var stepStart: (distance: Double, elapsed: TimeInterval) = (0, 0)
    private var latest: (distance: Double, elapsed: TimeInterval) = (0, 0)

    public init(plan: IntervalPlan) {
        self.plan = plan
        steps = plan.steps
    }

    public var isFinished: Bool { index >= steps.count }
    public var currentStep: IntervalStep? { isFinished ? nil : steps[index] }

    /// Actualiza con la distancia total y el tiempo activo. Devuelve los pasos
    /// que empiezan (puede ser más de uno si llegan datos con retraso).
    @discardableResult
    public mutating func update(distance: Double, elapsed: TimeInterval) -> [IntervalProgress] {
        latest = (distance, elapsed)
        var started: [IntervalProgress] = []
        while let step = currentStep {
            let boundary: (distance: Double, elapsed: TimeInterval)
            switch step.goal {
            case let .time(target) where elapsed - stepStart.elapsed >= target:
                // El tiempo es exacto; la distancia en el cruce se aproxima con la actual.
                boundary = (distance, stepStart.elapsed + target)
            case let .distance(target) where distance - stepStart.distance >= target:
                boundary = (stepStart.distance + target, elapsed)
            default:
                return started
            }
            begin(index + 1, at: boundary)
            if let progress = progress() { started.append(progress) }
        }
        return started
    }

    /// Termina el paso actual (botón "Vuelta"). Devuelve el paso que empieza.
    @discardableResult
    public mutating func advance(distance: Double, elapsed: TimeInterval) -> IntervalProgress? {
        guard !isFinished else { return nil }
        latest = (distance, elapsed)
        begin(index + 1, at: (distance, elapsed))
        return progress()
    }

    public func progress() -> IntervalProgress? {
        guard let step = currentStep else { return nil }
        return IntervalProgress(
            step: step,
            index: index,
            count: steps.count,
            elapsed: max(0, latest.elapsed - stepStart.elapsed),
            distance: max(0, latest.distance - stepStart.distance)
        )
    }

    /// Progreso en un instante concreto (el tiempo avanza entre actualizaciones de distancia).
    public func progress(elapsed: TimeInterval, distance: Double) -> IntervalProgress? {
        guard let step = currentStep else { return nil }
        return IntervalProgress(step: step, index: index, count: steps.count, elapsed: max(0, elapsed - stepStart.elapsed), distance: max(0, distance - stepStart.distance))
    }

    private mutating func begin(_ newIndex: Int, at point: (distance: Double, elapsed: TimeInterval)) {
        index = newIndex
        stepStart = point
    }
}

/// Textos compactos de planes de intervalos ("10 min · 6 × 400 m / 1:30 · 5 min").
public enum IntervalPlanFormatter {
    public static func goal(_ goal: IntervalGoal, unit: UnitSystem = .metric, locale: Locale = .current) -> String {
        switch goal {
        case let .time(seconds):
            let whole = Int(seconds.rounded())
            if whole < 60 { return "\(whole) s" }
            if whole % 60 == 0 { return "\(whole / 60) min" }
            return HalsynFormat.duration(seconds)
        case let .distance(meters):
            if meters < unit.metersPerDistanceUnit {
                return "\(HalsynFormat.integer(meters, locale: locale)) m"
            }
            let units = meters / unit.metersPerDistanceUnit
            if abs(units - units.rounded()) < 0.001 {
                // Kilómetros (o millas) enteros sin decimales: "15 km".
                return "\(HalsynFormat.integer(units.rounded(), locale: locale)) \(unit.distanceUnitSymbol)"
            }
            return "\(HalsynFormat.distance(meters: meters, unit: unit, locale: locale)) \(unit.distanceUnitSymbol)"
        case .open:
            // Paso que termina al pulsar Vuelta.
            return NSLocalizedString("hasta Vuelta", bundle: .main, comment: "")
        }
    }

    public static func summary(_ plan: IntervalPlan, unit: UnitSystem = .metric, locale: Locale = .current) -> String {
        var parts: [String] = []
        if let warmup = plan.warmup { parts.append(goal(warmup, unit: unit, locale: locale)) }
        // Un fondo de un solo bloque se escribe sin "1 ×".
        var block = plan.kind == .long && plan.repeats == 1
            ? goal(plan.work, unit: unit, locale: locale)
            : "\(plan.repeats) × \(goal(plan.work, unit: unit, locale: locale))"
        if plan.repeats > 1 {
            block += " / \(goal(plan.recovery, unit: unit, locale: locale))"
        }
        parts.append(block)
        if let cooldown = plan.cooldown { parts.append(goal(cooldown, unit: unit, locale: locale)) }
        return parts.joined(separator: " · ")
    }
}
